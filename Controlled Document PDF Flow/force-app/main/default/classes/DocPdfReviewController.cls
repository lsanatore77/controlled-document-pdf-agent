/**
 * DocPdfReviewController
 * ------------------------
 * Backs the docPdfReview component shown in the agent conversation. Returns the
 * recommendation rows of a proposal (or, when no Id is given, the user's latest
 * proposal that is ready for review), in display order. Read only.
 */
public with sharing class DocPdfReviewController {

    public class OptionDto {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String detail;
    }

    public class RowDto {
        @AuraEnabled public String id;
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String section;
        @AuraEnabled public String source;
        @AuraEnabled public String fieldType;
        @AuraEnabled public String proposedValue;
        @AuraEnabled public String proposedDisplay;
        @AuraEnabled public String decision;
        @AuraEnabled public String finalValue;
        @AuraEnabled public String finalDisplay;
        @AuraEnabled public String evidence;
        @AuraEnabled public Boolean required;
        @AuraEnabled public List<OptionDto> options = new List<OptionDto>();
    }

    public class ReviewData {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String proposalId;
        @AuraEnabled public String proposalName;
        @AuraEnabled public String status;
        @AuraEnabled public String fileName;
        @AuraEnabled public Integer pagesRead;
        @AuraEnabled public Integer totalPages;
        @AuraEnabled public String createdRecordId;
        @AuraEnabled public String createdRecordName;
        @AuraEnabled public List<RowDto> rows = new List<RowDto>();
    }

    @AuraEnabled
    public static ReviewData getReview(String proposalId) {
        ReviewData out = new ReviewData();
        try {
            Doc_PDF_Proposal__c p = findProposal(proposalId);
            if (p == null) {
                out.success = false;
                out.errorMessage = 'There is no PDF waiting for review. Ask me to create a controlled document from a PDF first.';
                return out;
            }
            out.proposalId = p.Id;
            out.proposalName = p.Name;
            out.status = p.Status__c;
            out.fileName = p.File_Name__c;
            out.pagesRead = p.Pages_Read__c == null ? null : p.Pages_Read__c.intValue();
            out.totalPages = p.Total_Pages__c == null ? null : p.Total_Pages__c.intValue();
            out.createdRecordId = p.Created_Record_Id__c;
            out.createdRecordName = p.Created_Record_Name__c;

            for (Doc_PDF_Field__c f : [
                SELECT Id, Field_API_Name__c, Field_Label__c, Section__c, Source__c, Field_Type__c,
                       Proposed_Value__c, Proposed_Display__c, Decision__c, Final_Value__c, Final_Display__c,
                       Evidence__c, Required__c, Options_JSON__c
                FROM Doc_PDF_Field__c
                WHERE Proposal__c = :p.Id
                WITH USER_MODE
                ORDER BY Sort_Order__c
            ]) {
                RowDto r = new RowDto();
                r.id = f.Id;
                r.apiName = f.Field_API_Name__c;
                r.label = f.Field_Label__c;
                r.section = f.Section__c;
                r.source = f.Source__c;
                r.fieldType = f.Field_Type__c;
                r.proposedValue = f.Proposed_Value__c;
                r.proposedDisplay = f.Proposed_Display__c;
                r.decision = f.Decision__c;
                r.finalValue = f.Final_Value__c;
                r.finalDisplay = f.Final_Display__c;
                r.evidence = f.Evidence__c;
                r.required = f.Required__c;
                if (String.isNotBlank(f.Options_JSON__c)) {
                    r.options = (List<OptionDto>) JSON.deserialize(f.Options_JSON__c, List<OptionDto>.class);
                }
                out.rows.add(r);
            }
        } catch (Exception e) {
            out.success = false;
            out.errorMessage = 'Could not load the review: ' + e.getMessage();
        }
        return out;
    }

    public class SaveResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer leftCount = 0;
    }

    /**
     * Saves the user's decisions the moment they make them in the review component, so the
     * Create step reads them from the proposal even if the agent does not pass the component's value.
     */
    @AuraEnabled
    public static SaveResult saveDecisions(String proposalId, String decisionsJson) {
        SaveResult out = new SaveResult();
        try {
            Doc_PDF_Proposal__c p = findProposal(proposalId);
            if (p == null) {
                out.errorMessage = 'There is no PDF waiting for review.';
                return out;
            }
            if (p.Status__c == 'Created') {
                out.errorMessage = 'This PDF was already used to create ' + p.Created_Record_Name__c + '.';
                return out;
            }
            List<Doc_PDF_Field__c> rows = [
                SELECT Id, Field_API_Name__c, Field_Label__c, Field_Type__c, Proposed_Value__c, Proposed_Display__c,
                       Decision__c, Final_Value__c, Final_Display__c, Required__c
                FROM Doc_PDF_Field__c
                WHERE Proposal__c = :p.Id
                WITH USER_MODE
            ];
            DocPdfCreateDocumentAction.applyDecisions(rows, decisionsJson);
            update as user rows;
            for (Doc_PDF_Field__c f : rows) {
                if (DocPdfCreateDocumentAction.isBlocked(f)) {
                    out.leftCount++;
                }
            }
            out.success = true;
        } catch (Exception e) {
            out.errorMessage = 'Could not save your choices: ' + e.getMessage();
        }
        return out;
    }

    /** The given proposal, or the user's latest one that is ready for review. Also used by DocPdfCreateDocumentAction. */
    public static Doc_PDF_Proposal__c findProposal(String proposalId) {
        List<Doc_PDF_Proposal__c> ps;
        if (String.isNotBlank(proposalId)) {
            Id pid = Id.valueOf(proposalId.trim());
            ps = [
                SELECT Id, Name, Status__c, File_Name__c, Pages_Read__c, Total_Pages__c,
                       Created_Record_Id__c, Created_Record_Name__c
                FROM Doc_PDF_Proposal__c WHERE Id = :pid WITH USER_MODE LIMIT 1
            ];
        } else {
            Id me = UserInfo.getUserId();
            ps = [
                SELECT Id, Name, Status__c, File_Name__c, Pages_Read__c, Total_Pages__c,
                       Created_Record_Id__c, Created_Record_Name__c
                FROM Doc_PDF_Proposal__c
                WHERE OwnerId = :me AND Status__c = 'Ready for Review'
                WITH USER_MODE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
        }
        return ps.isEmpty() ? null : ps[0];
    }
}
