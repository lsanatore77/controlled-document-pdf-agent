/**
 * DocPdfResolveProposalAction
 * -----------------------------
 * First step of the Doc_From_PDF_Analyze flow. Finds the proposal to analyze, so the
 * flow works even when the agent does not pass a Proposal Id:
 *   1. the given Proposal Id, when it has a PDF on it;
 *   2. otherwise the running user's most recent Draft proposal (last 24 hours) that has a PDF,
 *      which is the one the upload component just recorded.
 * Read only, so the Google Vision callout can still follow it in the same transaction.
 */
public with sharing class DocPdfResolveProposalAction {

    public class Request {
        @InvocableVariable(label='Proposal Id' description='Optional. The Proposal Id from Select PDF, if the agent has it.')
        public String proposalId;
    }

    public class Result {
        @InvocableVariable(label='Found') public Boolean found;
        @InvocableVariable(label='Proposal Id') public String proposalId;
        @InvocableVariable(label='Content Version Id') public String contentVersionId;
        @InvocableVariable(label='File Name') public String fileName;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(
        label='Find PDF Proposal to Analyze'
        description='Returns the proposal and PDF to analyze: the given Proposal Id, or the user\'s latest proposal with a PDF chosen.'
    )
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            out.add(resolve(req == null ? null : req.proposalId));
        }
        return out;
    }

    public static Result resolve(String proposalId) {
        Result r = new Result();
        r.found = false;
        try {
            Doc_PDF_Proposal__c p = null;
            if (String.isNotBlank(proposalId)) {
                Id pid = Id.valueOf(proposalId.trim());
                List<Doc_PDF_Proposal__c> given = [
                    SELECT Id, Content_Version_Id__c, File_Name__c, Status__c
                    FROM Doc_PDF_Proposal__c
                    WHERE Id = :pid
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!given.isEmpty() && String.isNotBlank(given[0].Content_Version_Id__c)) {
                    p = given[0];
                }
            }
            if (p == null) {
                p = latestWithFile();
            }
            if (p == null) {
                r.message = 'No PDF has been chosen yet. Upload a PDF or pick one from the list first.';
                return r;
            }
            r.found = true;
            r.proposalId = p.Id;
            r.contentVersionId = p.Content_Version_Id__c;
            r.fileName = p.File_Name__c;
        } catch (Exception e) {
            r.message = 'I could not find the PDF to read: ' + e.getMessage();
        }
        return r;
    }

    /** The running user's most recent Draft proposal from the last 24 hours that has a PDF on it. */
    public static Doc_PDF_Proposal__c latestWithFile() {
        Id me = UserInfo.getUserId();
        List<Doc_PDF_Proposal__c> ps = [
            SELECT Id, Content_Version_Id__c, Content_Document_Id__c, File_Name__c, Status__c
            FROM Doc_PDF_Proposal__c
            WHERE OwnerId = :me
            AND Status__c = 'Draft'
            AND Content_Version_Id__c != null
            AND LastModifiedDate = LAST_N_DAYS:1
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return ps.isEmpty() ? null : ps[0];
    }
}
