/**
 * DocPdfUploadController
 * ------------------------
 * Backs the docPdfUpload component shown in the agent conversation. Opens (or
 * reuses) today's draft proposal for the user, so the upload box has a record to
 * attach the file to, and lists the user's recent PDFs to pick from instead.
 */
public with sharing class DocPdfUploadController {

    public class RecentFile {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String sizeLabel;
        @AuraEnabled public String modifiedLabel;
    }

    public class StartData {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String proposalId;
        @AuraEnabled public List<RecentFile> recentFiles = new List<RecentFile>();
    }

    @AuraEnabled
    public static StartData start() {
        StartData out = new StartData();
        try {
            Id me = UserInfo.getUserId();
            List<Doc_PDF_Proposal__c> drafts = [
                SELECT Id FROM Doc_PDF_Proposal__c
                WHERE OwnerId = :me AND Status__c = 'Draft' AND Content_Document_Id__c = null
                AND CreatedDate = LAST_N_DAYS:1
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            Doc_PDF_Proposal__c p;
            if (drafts.isEmpty()) {
                p = new Doc_PDF_Proposal__c(Status__c = 'Draft');
                insert as user p;
            } else {
                p = drafts[0];
            }
            out.proposalId = p.Id;

            for (ContentDocument d : [
                SELECT Id, Title, ContentSize, LastModifiedDate
                FROM ContentDocument
                WHERE FileType = 'PDF' AND OwnerId = :me
                ORDER BY LastModifiedDate DESC
                LIMIT 6
            ]) {
                RecentFile f = new RecentFile();
                f.id = d.Id;
                f.title = d.Title;
                f.sizeLabel = sizeLabel(d.ContentSize);
                f.modifiedLabel = d.LastModifiedDate.date().format();
                out.recentFiles.add(f);
            }
        } catch (Exception e) {
            out.success = false;
            out.errorMessage = 'Could not start: ' + e.getMessage();
        }
        return out;
    }

    public class SelectResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String proposalId;
        @AuraEnabled public String fileName;
    }

    /**
     * Saves the chosen PDF on the proposal as soon as the user picks or uploads it,
     * so the Analyze PDF step finds it even if the agent does not pass the component's value.
     */
    @AuraEnabled
    public static SelectResult selectFile(String proposalId, String contentDocumentId) {
        SelectResult out = new SelectResult();
        DocPdfFileSelection s = new DocPdfFileSelection();
        s.proposalId = proposalId;
        s.contentDocumentId = contentDocumentId;
        if (String.isBlank(contentDocumentId)) {
            out.errorMessage = 'No file was chosen.';
            return out;
        }
        DocPdfSelectFileAction.Result r = DocPdfSelectFileAction.runOne(s);
        out.success = r.success == true;
        out.errorMessage = out.success ? null : r.message;
        out.proposalId = r.proposalId;
        out.fileName = r.fileName;
        return out;
    }

    @TestVisible
    private static String sizeLabel(Integer bytes) {
        if (bytes == null) {
            return '';
        }
        if (bytes < 1024 * 1024) {
            return Math.max(1, Math.round(bytes / 1024.0)) + ' KB';
        }
        return (Decimal.valueOf(bytes) / (1024 * 1024)).setScale(1) + ' MB';
    }
}
