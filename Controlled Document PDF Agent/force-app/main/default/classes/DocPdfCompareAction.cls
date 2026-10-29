/**
 * DocPdfCompareAction
 * ---------------------
 * Agent action "Compare PDF": compares the PDF the user chose (Select PDF) with the
 * Primary Content of an existing Controlled Document.
 *   1. finds the Controlled Document (record Id from the page, or a document number / name),
 *   2. finds its Primary Content PDF (else its Secondary Content, when that is a PDF),
 *   3. reads both with Google Vision (the existing document's text is cached per file version),
 *   4. decides whether the PDF is a version of it (DocPdfMatchService),
 *   5. if so, compares them and writes the summary (DocPdfCompareService),
 *   6. saves the result on the Doc PDF Proposal (Mode Compare, Status Compared).
 * Callouts come first, then all DML, as Apex requires. Nothing on the Controlled Document changes.
 */
global with sharing class DocPdfCompareAction {

    /** Tests set this to compare with an in-memory document, where the org's validation blocks inserting one. */
    @TestVisible
    private static compliancequest__SQX_Controlled_Document__c testDocument;

    global class Request {
        @InvocableVariable(label='Controlled Document Id' description='The Controlled Document to compare with: the record the user is on.')
        global String controlledDocumentId;
        @InvocableVariable(label='Document Number' description='Optional. A document number or name (SOP-44123 or SOP-44123[002]) when there is no record Id.')
        global String documentNumber;
        @InvocableVariable(label='Proposal Id' description='Optional. The Proposal Id from Select PDF. Blank: the PDF the user just chose.')
        global String proposalId;
        @InvocableVariable(label='Compare Anyway' description='True to compare even when the PDF is only possibly related.')
        global Boolean compareAnyway;
    }

    global class Result {
        @InvocableVariable(label='Success') global Boolean success;
        @InvocableVariable(label='Compared' description='True when the comparison was made.') global Boolean compared;
        @InvocableVariable(label='Verdict' description='Version, Rewritten, Likely Version, Possibly Related or Different.') global String verdict;
        @InvocableVariable(label='Message' description='Plain-language result to relay to the user.') global String message;
        @InvocableVariable(label='Comparison' description='Shown by the comparison component.') global DocPdfComparisonView comparison;
        @InvocableVariable(label='Proposal Id') global String proposalId;
        @InvocableVariable(label='Controlled Document Name') global String controlledDocumentName;
        @InvocableVariable(label='Other Document Id' description='When the PDF is a different document: an existing document that matches its number or title.') global String alternateDocumentId;
        @InvocableVariable(label='Other Document Name') global String alternateDocumentName;
    }

    @InvocableMethod(
        label='Compare PDF with Controlled Document'
        description='Checks whether the chosen PDF is a version of the Controlled Document, then compares it with the document\'s Primary Content and summarizes the differences. Changes no Controlled Document.'
        callout=true
    )
    global static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(runOne(req));
        }
        return out;
    }

    @TestVisible
    private static Result runOne(Request req) {
        Result r = new Result();
        r.success = false;
        r.compared = false;
        if (req == null) {
            req = new Request();
        }
        try {
            // ---- the Controlled Document
            compliancequest__SQX_Controlled_Document__c doc = testDocument != null
                ? testDocument : findDocument(req.controlledDocumentId, req.documentNumber);
            if (doc == null) {
                r.message = 'Open the Controlled Document you want to compare with, or tell me its document number.';
                return r;
            }
            r.controlledDocumentName = doc.Name;

            // ---- the new PDF
            DocPdfResolveProposalAction.Result p = DocPdfResolveProposalAction.resolve(req.proposalId);
            if (p.found != true) {
                r.message = 'No file has been chosen yet. Upload the new PDF or Word file, or pick one from the list first.';
                return r;
            }
            r.proposalId = p.proposalId;

            // ---- the existing document's PDF
            ContentVersion oldCv = currentPdf(doc);
            if (oldCv == null) {
                r.message = doc.Name + ' has no PDF or Word file to compare with. Its Primary Content is missing or is another file type, and there is no PDF or Word Secondary Content.';
                return r;
            }
            if (String.valueOf(oldCv.Id) == p.contentVersionId) {
                r.message = 'That is the same file as the Primary Content of ' + doc.Name + ', so there is nothing to compare.';
                return r;
            }

            // ---- read both (callouts before any DML)
            Doc_PDF_Text_Cache__c cache = cachedText(oldCv.Id);
            String oldText = cache == null ? null : cache.Text__c;
            GoogleVisionPdfService.Extraction oldRead;
            if (String.isBlank(oldText)) {
                oldRead = GoogleVisionPdfService.extract(oldCv.Id);
                if (oldRead.success != true || String.isBlank(oldRead.text)) {
                    r.message = 'I could not read the current version of ' + doc.Name + ': ' + oldRead.message;
                    return r;
                }
                oldText = oldRead.text;
            }
            GoogleVisionPdfService.Extraction newRead = GoogleVisionPdfService.extract(Id.valueOf(p.contentVersionId));
            if (newRead.success != true || String.isBlank(newRead.text)) {
                r.message = 'I could not read ' + p.fileName + ': ' + newRead.message;
                return r;
            }

            // ---- decide and compare (no DML)
            DocPdfMatchService.Settings st = DocPdfMatchService.loadSettings();
            DocPdfMatchService.Result m = DocPdfMatchService.match(doc.Name, doc.compliancequest__Document_Number__c,
                doc.compliancequest__Title__c, doc.compliancequest__Revision__c, oldText, newRead.text, st);
            Boolean doCompare = m.compareByDefault
                || (m.verdict == DocPdfMatchService.POSSIBLY_RELATED && req.compareAnyway == true);
            DocPdfCompareService.Comparison c = doCompare ? DocPdfCompareService.compare(oldText, newRead.text, m, st) : null;
            compliancequest__SQX_Controlled_Document__c alternate = m.verdict == DocPdfMatchService.DIFFERENT
                ? findAlternate(m, doc.Id) : null;

            // ---- save
            if (oldRead != null) {
                insert as user new Doc_PDF_Text_Cache__c(
                    Content_Version_Id__c = oldCv.Id,
                    Text__c = oldText.left(131072),
                    Pages_Read__c = oldRead.pagesRead,
                    Total_Pages__c = oldRead.totalPages);
            }
            Map<String, Object> view = viewModel(doc, oldCv, p, oldText, newRead, m, c, alternate, req.compareAnyway == true);
            String viewJson = JSON.serialize(view);
            if (viewJson.length() > 131072) {
                // Very long documents: keep the verdict and summary, drop the sentence detail.
                view.remove('sections');
                view.put('sectionsTrimmed', true);
                viewJson = JSON.serialize(view);
            }
            Doc_PDF_Proposal__c upd = new Doc_PDF_Proposal__c(
                Id = p.proposalId,
                Mode__c = 'Compare',
                Controlled_Document__c = doc.Id,
                Old_Content_Version_Id__c = oldCv.Id,
                Match_Verdict__c = m.verdict,
                Match_Score__c = m.shared,
                Comparison_JSON__c = viewJson.length() > 131072 ? null : viewJson,
                Summary__c = c == null ? m.text : c.summary,
                Pages_Read__c = newRead.pagesRead,
                Total_Pages__c = newRead.totalPages,
                Extracted_Text__c = newRead.text.left(131072));
            if (c != null) {
                upd.Status__c = 'Compared'; // otherwise it stays Draft, so "compare anyway" or "create" can reuse the PDF
            }
            update as user upd;

            // ---- result
            r.success = true;
            r.compared = c != null;
            r.verdict = m.verdict;
            r.comparison = new DocPdfComparisonView();
            r.comparison.proposalId = p.proposalId;
            r.comparison.verdict = m.verdict;
            r.comparison.title = m.title;
            if (alternate != null) {
                r.alternateDocumentId = alternate.Id;
                r.alternateDocumentName = alternate.Name + (String.isBlank(alternate.compliancequest__Title__c) ? '' : ', ' + alternate.compliancequest__Title__c);
            }
            if (c != null) {
                r.message = m.title + '. ' + c.summary;
            } else if (m.verdict == DocPdfMatchService.POSSIBLY_RELATED) {
                r.message = m.title + ': ' + m.text;
            } else {
                r.message = m.title + '. ' + m.text
                    + (alternate != null ? ' It matches ' + r.alternateDocumentName + '.' : '');
            }
        } catch (Exception e) {
            r.success = false;
            r.message = 'The comparison could not be completed: ' + e.getMessage();
        }
        return r;
    }

    // ------------------------------------------------------------------ lookups

    @TestVisible
    private static compliancequest__SQX_Controlled_Document__c findDocument(String recordId, String numberOrName) {
        if (String.isNotBlank(recordId)) {
            try {
                Id rid = Id.valueOf(recordId.trim());
                if (rid.getSobjectType() == compliancequest__SQX_Controlled_Document__c.SObjectType) {
                    List<compliancequest__SQX_Controlled_Document__c> ds = [
                        SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                               compliancequest__Revision__c, compliancequest__Content_Reference__c,
                               compliancequest__Secondary_Content_Reference__c
                        FROM compliancequest__SQX_Controlled_Document__c WHERE Id = :rid WITH USER_MODE LIMIT 1
                    ];
                    if (!ds.isEmpty()) {
                        return ds[0];
                    }
                }
            } catch (Exception e) {
                // Not an Id: fall through to the number.
            }
        }
        if (String.isBlank(numberOrName)) {
            return null;
        }
        String key = numberOrName.trim();
        String num = key.contains('[') ? key.substringBefore('[') : key;
        List<compliancequest__SQX_Controlled_Document__c> ds = [
            SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                   compliancequest__Revision__c, compliancequest__Content_Reference__c,
                   compliancequest__Secondary_Content_Reference__c, compliancequest__Document_Status__c
            FROM compliancequest__SQX_Controlled_Document__c
            WHERE Name = :key OR compliancequest__Document_Number__c = :num
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
        for (compliancequest__SQX_Controlled_Document__c d : ds) {
            if (d.Name == key) {
                return d;
            }
        }
        for (compliancequest__SQX_Controlled_Document__c d : ds) {
            if (d.compliancequest__Document_Status__c == 'Current') {
                return d;
            }
        }
        return ds.isEmpty() ? null : ds[0];
    }

    /** Latest version of the Primary Content when it is a PDF, else of the Secondary Content when that is. */
    @TestVisible
    private static ContentVersion currentPdf(compliancequest__SQX_Controlled_Document__c doc) {
        for (String ref : new List<String>{ doc.compliancequest__Content_Reference__c, doc.compliancequest__Secondary_Content_Reference__c }) {
            if (String.isBlank(ref)) {
                continue;
            }
            Id docId;
            try {
                docId = Id.valueOf(ref.trim());
            } catch (Exception e) {
                continue;
            }
            List<ContentVersion> cvs = [
                SELECT Id, Title, FileType, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :docId AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
            if (!cvs.isEmpty() && DocPdfDocxReader.isSupported(cvs[0].FileType)) {
                return cvs[0];
            }
        }
        return null;
    }

    private static Doc_PDF_Text_Cache__c cachedText(Id contentVersionId) {
        String cvId = contentVersionId;
        List<Doc_PDF_Text_Cache__c> cs = [
            SELECT Id, Text__c FROM Doc_PDF_Text_Cache__c
            WHERE Content_Version_Id__c = :cvId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return cs.isEmpty() ? null : cs[0];
    }

    /** For a different document: an existing Controlled Document with the PDF's number, else its title. */
    private static compliancequest__SQX_Controlled_Document__c findAlternate(DocPdfMatchService.Result m, Id excludeId) {
        if (String.isNotBlank(m.pdfNumber)) {
            String fullName = m.pdfNumber;
            String num = fullName.contains('[') ? fullName.substringBefore('[') : fullName;
            List<compliancequest__SQX_Controlled_Document__c> ds = [
                SELECT Id, Name, compliancequest__Title__c FROM compliancequest__SQX_Controlled_Document__c
                WHERE (compliancequest__Document_Number__c = :num OR Name = :fullName) AND Id != :excludeId
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!ds.isEmpty()) {
                return ds[0];
            }
        }
        if (String.isNotBlank(m.pdfTitle)) {
            String t = m.pdfTitle.left(255);
            List<compliancequest__SQX_Controlled_Document__c> ds = [
                SELECT Id, Name, compliancequest__Title__c FROM compliancequest__SQX_Controlled_Document__c
                WHERE compliancequest__Title__c = :t AND Id != :excludeId
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!ds.isEmpty()) {
                return ds[0];
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ view

    private static Map<String, Object> viewModel(compliancequest__SQX_Controlled_Document__c doc, ContentVersion oldCv,
                                                 DocPdfResolveProposalAction.Result p, String oldText,
                                                 GoogleVisionPdfService.Extraction newRead, DocPdfMatchService.Result m,
                                                 DocPdfCompareService.Comparison c,
                                                 compliancequest__SQX_Controlled_Document__c alternate, Boolean compareAnyway) {
        Map<String, Object> v = new Map<String, Object>();
        v.put('documentId', doc.Id);
        v.put('documentName', doc.Name);
        v.put('documentTitle', doc.compliancequest__Title__c);
        v.put('oldFileName', oldCv.Title);
        v.put('newFileName', p.fileName);
        v.put('newPages', newRead.pagesRead);
        v.put('verdict', m.verdict);
        v.put('verdictTitle', m.title);
        v.put('verdictText', m.text);
        v.put('tone', m.tone);
        v.put('shared', m.shared);
        v.put('revisionDirection', m.revisionDirection);
        v.put('reasons', m.reasons);
        v.put('compared', c != null);
        v.put('comparedAnyway', c != null && m.verdict == DocPdfMatchService.POSSIBLY_RELATED && compareAnyway);
        if (alternate != null) {
            v.put('alternateId', alternate.Id);
            v.put('alternateName', alternate.Name);
            v.put('alternateTitle', alternate.compliancequest__Title__c);
        }
        if (c != null) {
            v.put('summary', c.summary);
            v.put('summarySource', c.summarySource);
            v.put('changeScope', c.changeScope);
            v.put('changeScopeReason', c.changeScopeReason);
            v.put('changesText', c.changesText);
            v.put('header', c.header);
            v.put('sections', c.sections);
            v.put('changedCount', c.changedCount);
            v.put('addedCount', c.addedCount);
            v.put('removedCount', c.removedCount);
            v.put('unchangedCount', c.unchangedCount);
        }
        return v;
    }
}
