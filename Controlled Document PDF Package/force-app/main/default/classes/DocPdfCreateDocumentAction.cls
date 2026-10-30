/**
 * DocPdfCreateDocumentAction
 * ----------------------------
 * Agent action behind the review component. The agent shows docPdfReview (the
 * docPdfReviewType editor); when the user submits, this:
 *   1. saves the user's decision on every row (the component also saves each decision as it is
 *      made, so when the agent passes no review the saved decisions are used),
 *   2. stops with a list if anything is still undecided or a required value is blank,
 *   3. creates the Controlled Document (record type Controlled_Document) as a Draft
 *      with the accepted / edited values, running as the user,
 *   4. adds any accepted related documents and training requirements,
 *   5. links the PDF to the new record and sets it as the document's Primary Content,
 *   6. marks the proposal Created.
 * Fixed rows (Doc PDF Field Config: Fixed Value or not Editable) are written as set up.
 * Numbering: the Template follows the final Document Category (Category Templates on Doc PDF
 * Agent Setting) unless the user picked a template themselves; ComplianceQuest numbers the document
 * from it. With no released template, or when ComplianceQuest leaves the number blank, the Document
 * Number row is used (the category prefix plus the next free number, checked again here).
 * A document is never saved without a number.
 */
global with sharing class DocPdfCreateDocumentAction {

    global class Request {
        @InvocableVariable(label='Review' description='The user\'s decisions from the review component. Optional: the component also saves each decision as it is made.')
        global DocPdfReview review;
    }

    global class Result {
        @InvocableVariable(label='Success') global Boolean success;
        @InvocableVariable(label='Record Id') global String recordId;
        @InvocableVariable(label='Document Name' description='Document Number [Rev] of the new record.') global String documentName;
        @InvocableVariable(label='Summary' description='Plain-language result to relay to the user.') global String summary;
        @InvocableVariable(label='Undecided Count' description='Rows still needing a decision; nothing is created while this is above 0.') global Integer undecidedCount;
    }

    public class Decision {
        public String id;
        public String decision;
        public String value;
        public String display;
    }

    @InvocableMethod(
        label='Review Fields and Create Controlled Document'
        description='Shows the field recommendations for the user to accept, edit or clear, then creates the Controlled Document as a Draft with the values the user kept, adds related documents and training requirements, and attaches the PDF.'
    )
    global static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(runOne(req.review));
        }
        return out;
    }

    @TestVisible
    private static Result runOne(DocPdfReview review) {
        Result r = new Result();
        r.success = false;
        r.undecidedCount = 0;
        try {
            Doc_PDF_Proposal__c proposal = DocPdfReviewController.findProposal(review == null ? null : review.proposalId);
            if (proposal == null) {
                r.summary = 'There is no PDF waiting for review.';
                return r;
            }
            proposal = [
                SELECT Id, Name, Status__c, Content_Document_Id__c, File_Name__c, Created_Record_Id__c, Created_Record_Name__c
                FROM Doc_PDF_Proposal__c WHERE Id = :proposal.Id WITH USER_MODE LIMIT 1
            ];
            if (proposal.Status__c == 'Created' && proposal.Created_Record_Id__c != null) {
                r.success = true;
                r.recordId = proposal.Created_Record_Id__c;
                r.documentName = proposal.Created_Record_Name__c;
                r.summary = 'This PDF was already used to create ' + proposal.Created_Record_Name__c + '.';
                return r;
            }

            List<Doc_PDF_Field__c> rows = [
                SELECT Id, Field_API_Name__c, Field_Label__c, Section__c, Field_Type__c, Proposed_Value__c,
                       Proposed_Display__c, Decision__c, Final_Value__c, Final_Display__c, Required__c
                FROM Doc_PDF_Field__c
                WHERE Proposal__c = :proposal.Id
                WITH USER_MODE
                ORDER BY Sort_Order__c
            ];
            applyDecisions(rows, review == null ? null : review.decisionsJson);
            update as user rows;

            List<String> blocked = new List<String>();
            for (Doc_PDF_Field__c f : rows) {
                if (isBlocked(f)) {
                    blocked.add(f.Field_Label__c);
                }
            }
            if (!blocked.isEmpty()) {
                r.undecidedCount = blocked.size();
                r.summary = 'Nothing was created yet. ' + blocked.size() + (blocked.size() == 1 ? ' field still needs' : ' fields still need')
                    + ' a decision or a value: ' + String.join(blocked, ', ') + '.';
                return r;
            }

            // ---- the Controlled Document
            Map<String, Schema.SObjectField> fieldMap =
                compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().fields.getMap();
            compliancequest__SQX_Controlled_Document__c doc = new compliancequest__SQX_Controlled_Document__c();
            Schema.RecordTypeInfo rt = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName().get('Controlled_Document');
            if (rt != null) {
                doc.RecordTypeId = rt.getRecordTypeId();
            }
            Integer setCount = 0;
            Integer blankCount = 0;
            for (Doc_PDF_Field__c f : rows) {
                if (!isRecordField(f) || isNumberingField(f)) {
                    continue;
                }
                String v = f.Final_Value__c;
                if (String.isBlank(v)) {
                    blankCount++;
                    f.Outcome__c = 'Left blank';
                    continue;
                }
                Schema.SObjectField sf = f.Field_API_Name__c == 'OwnerId'
                    ? fieldMap.get('ownerid') : fieldMap.get(f.Field_API_Name__c.toLowerCase());
                if (sf == null || !sf.getDescribe().isCreateable()) {
                    f.Outcome__c = 'Skipped: you cannot set this field';
                    continue;
                }
                try {
                    doc.put(sf, coerce(sf.getDescribe(), v));
                    f.Outcome__c = 'Set';
                    setCount++;
                } catch (Exception e) {
                    f.Outcome__c = ('Skipped: ' + e.getMessage()).left(255);
                }
            }

            // ---- template and number
            NumberPlan plan = planNumber(rows);
            Schema.SObjectField templateField = fieldMap.get(DocPdfRecommendationBuilder.TEMPLATE_FIELD);
            Schema.SObjectField numberField = fieldMap.get(DocPdfRecommendationBuilder.NUMBER_FIELD);
            if (plan.templateId != null && templateField != null && templateField.getDescribe().isCreateable()) {
                doc.put(templateField, plan.templateId);
            } else {
                plan.templateId = null;
            }
            // The values set so far, kept so a retry can start from a clean record: ComplianceQuest's
            // triggers may have changed the first attempt's record in memory.
            Map<String, Object> setValues = new Map<String, Object>(doc.getPopulatedFieldsAsMap());
            String usedNumber;
            String firstError;
            Boolean saved = false;
            if (plan.templateId != null) {
                // ComplianceQuest numbers it from the template.
                Savepoint sp = Database.setSavepoint();
                try {
                    insert as user doc;
                    String assigned = (String) [
                        SELECT compliancequest__Document_Number__c FROM compliancequest__SQX_Controlled_Document__c
                        WHERE Id = :doc.Id LIMIT 1
                    ].compliancequest__Document_Number__c;
                    if (String.isBlank(assigned)) {
                        Database.rollback(sp);
                        firstError = 'ComplianceQuest did not number it from template ' + plan.templateName + '.';
                    } else {
                        saved = true;
                    }
                } catch (DmlException e) {
                    Database.rollback(sp);
                    firstError = e.getDmlMessage(0);
                }
            }
            if (!saved) {
                if (numberField == null || !numberField.getDescribe().isCreateable()) {
                    update as user rows;
                    r.summary = 'ComplianceQuest did not accept the new document' + (firstError == null ? '.' : ': ' + firstError)
                        + ' You cannot set the Document Number, so nothing was created.';
                    return r;
                }
                usedNumber = DocPdfNumbering.freeNumber(plan.wantedNumber, plan.prefix);
                doc = freshCopy(setValues);
                doc.put(numberField, usedNumber);
                Savepoint sp2 = Database.setSavepoint();
                try {
                    insert as user doc;
                } catch (DmlException e2) {
                    Database.rollback(sp2);
                    update as user rows;
                    r.summary = 'ComplianceQuest did not accept the new document: '
                        + (firstError == null ? '' : firstError + ' Then, with number ' + usedNumber + ': ')
                        + e2.getDmlMessage(0) + ' Change the value in the review and submit again.';
                    return r;
                }
            }
            for (Doc_PDF_Field__c f : rows) {
                String api = f.Field_API_Name__c == null ? '' : f.Field_API_Name__c.toLowerCase();
                if (api == DocPdfRecommendationBuilder.NUMBER_FIELD) {
                    f.Outcome__c = usedNumber == null ? 'Numbered by the template' : ('Set: ' + usedNumber).left(255);
                } else if (api == DocPdfRecommendationBuilder.TEMPLATE_FIELD) {
                    f.Outcome__c = plan.templateId == null ? 'Left blank' : ('Set: ' + plan.templateName).left(255);
                }
            }

            // ---- related records (best effort: the document stays even if one fails)
            List<String> notes = new List<String>();
            List<compliancequest__SQX_Related_Document__c> related = new List<compliancequest__SQX_Related_Document__c>();
            List<Doc_PDF_Field__c> relatedRows = new List<Doc_PDF_Field__c>();
            List<compliancequest__SQX_Requirement__c> reqs = new List<compliancequest__SQX_Requirement__c>();
            List<Doc_PDF_Field__c> reqRows = new List<Doc_PDF_Field__c>();
            for (Doc_PDF_Field__c f : rows) {
                if (f.Decision__c == 'clear' || String.isBlank(f.Final_Value__c)) {
                    continue;
                }
                if (f.Field_Type__c == 'relatedDocument') {
                    related.add(new compliancequest__SQX_Related_Document__c(
                        compliancequest__Controlled_Document__c = doc.Id,
                        compliancequest__Referenced_Document__c = Id.valueOf(f.Final_Value__c)));
                    relatedRows.add(f);
                } else if (f.Field_Type__c == 'jobFunction') {
                    reqs.add(new compliancequest__SQX_Requirement__c(
                        compliancequest__SQX_Controlled_Document__c = doc.Id,
                        compliancequest__SQX_Job_Function__c = Id.valueOf(f.Final_Value__c)));
                    reqRows.add(f);
                }
            }
            Integer relatedOk = saveChildren(related, relatedRows, notes);
            Integer reqOk = saveChildren(reqs, reqRows, notes);

            Boolean fileLinked = linkFile(proposal.Content_Document_Id__c, doc.Id, notes);
            Boolean primarySet = fileLinked && setPrimaryContent(proposal.Content_Document_Id__c, doc.Id, fieldMap, notes);
            for (Doc_PDF_Field__c f : rows) {
                if (f.Field_API_Name__c == DocPdfRecommendationBuilder.PRIMARY_CONTENT_KEY) {
                    f.Outcome__c = primarySet ? 'Set' : (fileLinked ? 'Attached only' : 'Not attached');
                }
            }

            String name = nameRecord(doc.Id);
            proposal.Status__c = 'Created';
            proposal.Created_Record_Id__c = doc.Id;
            proposal.Created_Record_Name__c = name == null ? null : name.left(80);
            update as user proposal;
            update as user rows;

            r.success = true;
            r.recordId = doc.Id;
            r.documentName = name;
            String s = 'Created ' + name + ' as a Draft. ' + setCount + (setCount == 1 ? ' field was' : ' fields were')
                + ' set from your review and ' + blankCount + ' left blank.';
            if (relatedOk > 0) {
                s += ' Added ' + relatedOk + (relatedOk == 1 ? ' related document.' : ' related documents.');
            }
            if (reqOk > 0) {
                s += ' Added ' + reqOk + (reqOk == 1 ? ' training requirement.' : ' training requirements.');
            }
            if (usedNumber == null) {
                s += ' ComplianceQuest numbered it from template ' + plan.templateName + '.';
            } else {
                s += ' Its number is ' + usedNumber + (firstError != null
                    ? ', used because ComplianceQuest did not number it (' + firstError + ').'
                    : usedNumber == plan.wantedNumber ? ', from your review.'
                    : ', the next free ' + usedNumber.substringBeforeLast('-') + ' number.');
            }
            s += primarySet ? ' The uploaded file is the document\'s Primary Content.' : (fileLinked ? ' The uploaded file is attached to the record.' : '');
            if (!notes.isEmpty()) {
                s += ' Not done: ' + String.join(notes, ' ');
            }
            s += ' Next step: open the record and submit it for approval.';
            r.summary = s;
        } catch (Exception e) {
            r.success = false;
            r.summary = 'The document could not be created: ' + e.getMessage();
        }
        return r;
    }

    // ------------------------------------------------------------------ decisions

    public static void applyDecisions(List<Doc_PDF_Field__c> rows, String decisionsJson) {
        Map<String, Decision> byId = new Map<String, Decision>();
        if (String.isNotBlank(decisionsJson)) {
            for (Decision d : (List<Decision>) JSON.deserialize(decisionsJson, List<Decision>.class)) {
                if (d != null && d.id != null) {
                    byId.put(d.id.left(15), d);
                }
            }
        }
        for (Doc_PDF_Field__c f : rows) {
            if (f.Decision__c == 'locked') {
                // Fixed values are written as set up; information rows never are.
                Boolean info = f.Field_Type__c == 'info' || (f.Field_API_Name__c != null && f.Field_API_Name__c.startsWith('info:'));
                f.Final_Value__c = info ? null : f.Proposed_Value__c;
                f.Final_Display__c = info ? null : f.Proposed_Display__c;
                continue;
            }
            Decision d = f.Id == null ? null : byId.get(String.valueOf(f.Id).left(15));
            if (d != null && String.isNotBlank(d.decision)) {
                f.Decision__c = d.decision;
                if (d.decision == 'edit') {
                    f.Final_Value__c = String.isBlank(d.value) ? null : d.value;
                    f.Final_Display__c = String.isBlank(d.display) ? (d.value == null ? null : d.value.left(255)) : d.display.left(255);
                }
            }
            if (f.Decision__c == 'accept') {
                f.Final_Value__c = f.Proposed_Value__c;
                f.Final_Display__c = f.Proposed_Display__c;
            } else if (f.Decision__c == 'clear' || f.Decision__c == 'undecided') {
                f.Final_Value__c = null;
                f.Final_Display__c = null;
            }
        }
    }

    public static Boolean isBlocked(Doc_PDF_Field__c f) {
        if (f.Decision__c == 'locked') {
            return false;
        }
        if (f.Decision__c == null || f.Decision__c == 'undecided') {
            return true;
        }
        return f.Required__c == true && String.isBlank(f.Final_Value__c);
    }

    /** The template and number to use, from the final review values. */
    public class NumberPlan {
        public Id templateId;
        public String templateName;
        public String category;
        public String prefix;
        public String wantedNumber;
    }

    private static Boolean isNumberingField(Doc_PDF_Field__c f) {
        String api = f.Field_API_Name__c == null ? '' : f.Field_API_Name__c.toLowerCase();
        return api == DocPdfRecommendationBuilder.TEMPLATE_FIELD || api == DocPdfRecommendationBuilder.NUMBER_FIELD;
    }

    /**
     * Template: the one the user picked (Edit), else the released template for the final Category,
     * else the reviewed value. Number: the one the user typed (Edit), else the next free number for
     * the final Category's prefix.
     */
    @TestVisible
    private static NumberPlan planNumber(List<Doc_PDF_Field__c> rows) {
        NumberPlan p = new NumberPlan();
        Doc_PDF_Field__c templateRow;
        Doc_PDF_Field__c numberRow;
        for (Doc_PDF_Field__c f : rows) {
            String api = f.Field_API_Name__c == null ? '' : f.Field_API_Name__c.toLowerCase();
            if (api == DocPdfRecommendationBuilder.CATEGORY_FIELD) {
                p.category = f.Final_Value__c;
            } else if (api == DocPdfRecommendationBuilder.TEMPLATE_FIELD) {
                templateRow = f;
            } else if (api == DocPdfRecommendationBuilder.NUMBER_FIELD) {
                numberRow = f;
            }
        }
        p.prefix = DocPdfNumbering.prefixFor(p.category);

        if (templateRow != null && templateRow.Decision__c == 'edit') {
            setTemplate(p, templateRow.Final_Value__c, templateRow.Final_Display__c);
        } else {
            DocPdfNumbering.Template t = DocPdfNumbering.templateForCategory(p.category);
            if (t != null) {
                p.templateId = t.id;
                p.templateName = t.name;
            } else if (templateRow != null && DocPdfNumbering.forCategory(p.category) == null) {
                // No template set up for this category: keep what the review says.
                setTemplate(p, templateRow.Final_Value__c, templateRow.Final_Display__c);
            }
        }

        if (numberRow != null && numberRow.Decision__c == 'edit' && String.isNotBlank(numberRow.Final_Value__c)) {
            p.wantedNumber = numberRow.Final_Value__c.trim();
        }
        return p;
    }

    private static void setTemplate(NumberPlan p, String value, String display) {
        if (String.isBlank(value)) {
            return;
        }
        try {
            p.templateId = Id.valueOf(value);
            p.templateName = String.isBlank(display) ? value : display;
        } catch (Exception e) {
            p.templateId = null;
        }
    }

    /**
     * The record's Name. Some orgs' ComplianceQuest leaves the Name as the record Id; then it is set to
     * Document Number[Revision], as ComplianceQuest names documents (POL-000001[001]).
     */
    @TestVisible
    private static String nameRecord(Id docId) {
        compliancequest__SQX_Controlled_Document__c d = [
            SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Revision__c
            FROM compliancequest__SQX_Controlled_Document__c WHERE Id = :docId LIMIT 1
        ];
        String wanted = nameFor(d);
        if (wanted == null) {
            return d.Name;
        }
        try {
            compliancequest__SQX_Controlled_Document__c upd = new compliancequest__SQX_Controlled_Document__c(Id = d.Id, Name = wanted);
            // ComplianceQuest's Document And Rev field, when it can be set (it is blank in the same orgs).
            Schema.SObjectField andRev = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
                .fields.getMap().get('compliancequest__document_and_rev__c');
            if (andRev != null && andRev.getDescribe().isUpdateable()) {
                upd.put(andRev, wanted);
            }
            update as user upd;
            return wanted;
        } catch (Exception e) {
            return d.Name;
        }
    }

    /** Document Number[Revision] when the Name is still the record Id; null when the Name is fine. */
    @TestVisible
    private static String nameFor(compliancequest__SQX_Controlled_Document__c d) {
        String idName = d.Id == null ? null : String.valueOf(d.Id);
        Boolean nameIsId = String.isBlank(d.Name) || (idName != null && (d.Name == idName || d.Name == idName.left(15)));
        if (!nameIsId || String.isBlank(d.compliancequest__Document_Number__c)) {
            return null;
        }
        String rev = d.compliancequest__Revision__c;
        return (d.compliancequest__Document_Number__c + (String.isBlank(rev) ? '' : '[' + rev + ']')).left(80);
    }

    /** A new Controlled Document with only the given field values (no Id, nothing a trigger set). */
    @TestVisible
    private static compliancequest__SQX_Controlled_Document__c freshCopy(Map<String, Object> values) {
        compliancequest__SQX_Controlled_Document__c d = new compliancequest__SQX_Controlled_Document__c();
        for (String k : values.keySet()) {
            if (k.toLowerCase() != 'id') {
                d.put(k, values.get(k));
            }
        }
        return d;
    }

    @TestVisible
    private static Boolean isRecordField(Doc_PDF_Field__c f) {
        String api = f.Field_API_Name__c;
        return api != null && !api.startsWith('related:') && !api.startsWith('info:') && f.Field_Type__c != 'info';
    }

    @TestVisible
    private static Object coerce(Schema.DescribeFieldResult d, String v) {
        Schema.DisplayType t = d.getType();
        if (t == Schema.DisplayType.DATE) {
            return Date.valueOf(v);
        }
        if (t == Schema.DisplayType.DATETIME) {
            return Datetime.valueOf(v.replace('T', ' ').removeEnd('Z'));
        }
        if (t == Schema.DisplayType.BOOLEAN) {
            return v.equalsIgnoreCase('true');
        }
        if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
            return Decimal.valueOf(v);
        }
        if (t == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(v);
        }
        if (t == Schema.DisplayType.REFERENCE) {
            return Id.valueOf(v);
        }
        Integer max = d.getLength();
        return max > 0 && v.length() > max ? v.left(max) : v;
    }

    // ------------------------------------------------------------------ children

    @TestVisible
    private static Integer saveChildren(List<SObject> records, List<Doc_PDF_Field__c> rows, List<String> notes) {
        if (records.isEmpty()) {
            return 0;
        }
        Integer ok = 0;
        List<Database.SaveResult> results = Database.insert(records, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Doc_PDF_Field__c f = rows[i];
            if (results[i].isSuccess()) {
                ok++;
                f.Outcome__c = 'Created';
            } else {
                String msg = results[i].getErrors().isEmpty() ? 'unknown error' : results[i].getErrors()[0].getMessage();
                f.Outcome__c = ('Failed: ' + msg).left(255);
                notes.add(f.Field_Label__c + ' ' + f.Final_Display__c + ' (' + msg + ').');
            }
        }
        return ok;
    }

    @TestVisible
    private static Boolean linkFile(String contentDocumentId, Id recordId, List<String> notes) {
        if (String.isBlank(contentDocumentId)) {
            return false;
        }
        try {
            ContentDocumentLink link = new ContentDocumentLink(
                ContentDocumentId = Id.valueOf(contentDocumentId),
                LinkedEntityId = recordId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            insert as user link;
            return true;
        } catch (Exception e) {
            notes.add('Attaching the PDF (' + e.getMessage() + ').');
            return false;
        }
    }

    /** Sets the linked PDF as the Controlled Document's Primary Content, as ComplianceQuest stores it. */
    @TestVisible
    private static Boolean setPrimaryContent(String contentDocumentId, Id recordId,
                                             Map<String, Schema.SObjectField> fieldMap, List<String> notes) {
        Schema.SObjectField ref = fieldMap.get('compliancequest__content_reference__c');
        if (String.isBlank(contentDocumentId) || ref == null || !ref.getDescribe().isUpdateable()) {
            notes.add('Setting the PDF as Primary Content (you cannot edit the Primary Content field).');
            return false;
        }
        try {
            compliancequest__SQX_Controlled_Document__c upd = new compliancequest__SQX_Controlled_Document__c(Id = recordId);
            upd.put(ref, contentDocumentId);
            Schema.SObjectField method = fieldMap.get('compliancequest__primary_content_check_in_method__c');
            if (method != null && method.getDescribe().isUpdateable()) {
                upd.put(method, 'Manual');
            }
            update as user upd;
            return true;
        } catch (Exception e) {
            String msg = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
            notes.add('Setting the PDF as Primary Content (' + msg + '). The PDF is attached to the record.');
            return false;
        }
    }
}
