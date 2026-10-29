/**
 * DocPdfSelectFileAction
 * ------------------------
 * Agent action behind the upload component. The agent shows docPdfUpload (the
 * docPdfFileSelectionType editor); when the user submits, this checks the file is
 * a PDF and records it on the proposal. The agent then runs the
 * Doc_From_PDF_Analyze flow with the returned Proposal Id.
 */
global with sharing class DocPdfSelectFileAction {

    global class Request {
        @InvocableVariable(label='File Selection' description='The PDF the user uploaded or picked, from the upload component.' required=true)
        global DocPdfFileSelection selection;
    }

    global class Result {
        @InvocableVariable(label='Success') global Boolean success;
        @InvocableVariable(label='Proposal Id' description='Pass this to the Analyze PDF flow.') global String proposalId;
        @InvocableVariable(label='File Name') global String fileName;
        @InvocableVariable(label='Message' description='Plain-language result to relay to the user.') global String message;
    }

    @InvocableMethod(
        label='Select PDF for New Controlled Document'
        description='Shows the upload component so the user can upload or pick a PDF, then records the chosen PDF on a new proposal. Returns the Proposal Id for the Analyze PDF flow.'
    )
    global static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(runOne(req.selection));
        }
        return out;
    }

    /**
     * Records the chosen PDF on the proposal. Also called by the upload component the
     * moment the user picks or uploads a file, so the choice is saved even if the agent
     * does not pass the component's value to this action.
     */
    public static Result runOne(DocPdfFileSelection s) {
        Result r = new Result();
        r.success = false;
        try {
            if (s == null || String.isBlank(s.contentDocumentId)) {
                // The component already saved the choice: use it.
                Doc_PDF_Proposal__c saved = DocPdfResolveProposalAction.latestWithFile();
                if (saved != null) {
                    r.success = true;
                    r.proposalId = saved.Id;
                    r.fileName = saved.File_Name__c;
                    r.message = 'Got it: ' + saved.File_Name__c + '. Reading it now.';
                    return r;
                }
                r.message = 'No file was chosen. Upload a PDF or Word (.docx) file, or pick one from the list, then submit.';
                return r;
            }
            Id docId = Id.valueOf(s.contentDocumentId.trim());
            List<ContentVersion> cvs = [
                SELECT Id, Title, FileType, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :docId AND IsLatest = true
                WITH USER_MODE
                LIMIT 1
            ];
            if (cvs.isEmpty()) {
                r.message = 'I could not open that file. It may have been deleted, or you may not have access to it.';
                return r;
            }
            ContentVersion cv = cvs[0];
            if (!DocPdfDocxReader.isSupported(cv.FileType)) {
                r.message = DocPdfDocxReader.unsupportedMessage(cv.Title, cv.FileType);
                return r;
            }

            Doc_PDF_Proposal__c proposal;
            if (String.isNotBlank(s.proposalId)) {
                Id proposalId = Id.valueOf(s.proposalId.trim());
                List<Doc_PDF_Proposal__c> ps = [
                    SELECT Id, Status__c FROM Doc_PDF_Proposal__c
                    WHERE Id = :proposalId
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!ps.isEmpty() && ps[0].Status__c != 'Created') {
                    proposal = ps[0];
                }
            }
            if (proposal == null) {
                proposal = new Doc_PDF_Proposal__c(Status__c = 'Draft');
            }
            proposal.Status__c = 'Draft';
            proposal.Content_Document_Id__c = cv.ContentDocumentId;
            proposal.Content_Version_Id__c = cv.Id;
            proposal.File_Name__c = cv.Title;
            upsert as user proposal;

            r.success = true;
            r.proposalId = proposal.Id;
            r.fileName = cv.Title;
            r.message = 'Got it: ' + cv.Title + '. Reading it now.';
        } catch (Exception e) {
            r.message = 'I could not use that file: ' + e.getMessage();
        }
        return r;
    }
}
