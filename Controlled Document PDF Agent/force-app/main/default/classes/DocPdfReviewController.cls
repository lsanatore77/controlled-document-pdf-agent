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
        @AuraEnabled public String aiStatus;
        @AuraEnabled public List<RowDto> rows = new List<RowDto>();
        /** An existing document this file may be a new version of (DocPdfRevisionCheck), or null. */
        @AuraEnabled public MatchDto match;
    }

    public class MatchDto {
        @AuraEnabled public String documentId;
        @AuraEnabled public String name;
        @AuraEnabled public String documentNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String revision;
        @AuraEnabled public String status;
        @AuraEnabled public String kind;
        @AuraEnabled public String reason;
        @AuraEnabled public Boolean compared = false;
    }

    public class CompareResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean compared = false;
        @AuraEnabled public String verdict;
        @AuraEnabled public String message;
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
            out.aiStatus = p.AI_Status__c;
            if (p.Status__c != 'Created' && p.Mode__c != 'Compare') {
                try {
                    out.match = matchOf(p);
                } catch (Exception e) {
                    out.match = null; // The banner is a hint: the review still loads without it.
                }
            }

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

    /**
     * Compare button on the review's "new version?" banner: compares the file with the matched
     * document (DocPdfCompareAction). The review stays open; the comparison is saved on the proposal
     * and shown by the comparison component.
     */
    @AuraEnabled
    public static CompareResult compareWithMatch(String proposalId) {
        CompareResult out = new CompareResult();
        try {
            Doc_PDF_Proposal__c p = findProposal(proposalId);
            if (p == null || p.Controlled_Document__c == null) {
                out.message = 'There is no existing document to compare with.';
                return out;
            }
            if (p.Status__c == 'Created') {
                out.message = 'This file was already used to create ' + p.Created_Record_Name__c + '.';
                return out;
            }
            DocPdfCompareAction.Result r = DocPdfCompareAction.compareForReview(p.Id, p.Controlled_Document__c);
            out.success = r.success == true;
            out.compared = r.compared == true;
            out.verdict = r.verdict;
            out.message = r.message;
        } catch (Exception e) {
            out.message = 'The comparison could not be completed: ' + e.getMessage();
        }
        return out;
    }

    private static MatchDto matchOf(Doc_PDF_Proposal__c p) {
        if (p.Controlled_Document__c == null) {
            return null;
        }
        List<compliancequest__SQX_Controlled_Document__c> ds = [
            SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                   compliancequest__Revision__c, compliancequest__Document_Status__c
            FROM compliancequest__SQX_Controlled_Document__c
            WHERE Id = :p.Controlled_Document__c WITH USER_MODE LIMIT 1
        ];
        if (ds.isEmpty()) {
            return null;
        }
        compliancequest__SQX_Controlled_Document__c d = ds[0];
        MatchDto m = new MatchDto();
        m.documentId = d.Id;
        m.name = d.Name;
        m.documentNumber = d.compliancequest__Document_Number__c;
        m.title = d.compliancequest__Title__c;
        m.revision = d.compliancequest__Revision__c;
        m.status = d.compliancequest__Document_Status__c;
        m.kind = p.Match_Verdict__c;
        m.compared = String.isNotBlank(p.Old_Content_Version_Id__c);
        String shared = p.Match_Score__c == null ? '' : p.Match_Score__c.setScale(0) + '% of the text matches';
        if (p.Match_Verdict__c == DocPdfRevisionCheck.SAME_NUMBER) {
            m.reason = 'The file has the same document number (' + d.compliancequest__Document_Number__c + ')'
                + (shared == '' ? '' : ', and ' + shared);
        } else if (p.Match_Verdict__c == DocPdfRevisionCheck.SAME_CONTENT) {
            m.reason = 'Most of the text matches (' + p.Match_Score__c.setScale(0) + '%), though the number differs';
        } else if (p.Match_Verdict__c == DocPdfRevisionCheck.SAME_TITLE) {
            m.reason = 'The title matches' + (shared == '' ? '' : ', and ' + shared);
        } else {
            m.reason = 'It looks similar';
        }
        m.reason += '.';
        return m;
    }

    /** The given proposal, or the user's latest one that is ready for review. Also used by DocPdfCreateDocumentAction. */
    public static Doc_PDF_Proposal__c findProposal(String proposalId) {
        List<Doc_PDF_Proposal__c> ps;
        if (String.isNotBlank(proposalId)) {
            Id pid = Id.valueOf(proposalId.trim());
            ps = [
                SELECT Id, Name, Status__c, File_Name__c, Pages_Read__c, Total_Pages__c,
                       Created_Record_Id__c, Created_Record_Name__c, AI_Status__c,
                       Mode__c, Controlled_Document__c, Match_Verdict__c, Match_Score__c, Old_Content_Version_Id__c
                FROM Doc_PDF_Proposal__c WHERE Id = :pid WITH USER_MODE LIMIT 1
            ];
        } else {
            Id me = UserInfo.getUserId();
            ps = [
                SELECT Id, Name, Status__c, File_Name__c, Pages_Read__c, Total_Pages__c,
                       Created_Record_Id__c, Created_Record_Name__c, AI_Status__c,
                       Mode__c, Controlled_Document__c, Match_Verdict__c, Match_Score__c, Old_Content_Version_Id__c
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
