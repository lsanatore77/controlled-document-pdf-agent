/**
 * DocPdfComparisonController
 * Backs the docPdfComparison component: returns the saved comparison of a proposal
 * (or, when no Id is given, the user's latest comparison) as JSON. Read only.
 */
public with sharing class DocPdfComparisonController {

    public class ComparisonData {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String proposalId;
        @AuraEnabled public String comparisonJson;
    }

    @AuraEnabled
    public static ComparisonData getComparison(String proposalId) {
        ComparisonData out = new ComparisonData();
        try {
            List<Doc_PDF_Proposal__c> ps;
            if (String.isNotBlank(proposalId)) {
                Id pid = Id.valueOf(proposalId.trim());
                ps = [
                    SELECT Id, Comparison_JSON__c FROM Doc_PDF_Proposal__c
                    WHERE Id = :pid WITH USER_MODE LIMIT 1
                ];
            } else {
                Id me = UserInfo.getUserId();
                ps = [
                    SELECT Id, Comparison_JSON__c FROM Doc_PDF_Proposal__c
                    WHERE OwnerId = :me AND Mode__c = 'Compare' AND Match_Verdict__c != null
                    WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 1
                ];
            }
            if (ps.isEmpty() || String.isBlank(ps[0].Comparison_JSON__c)) {
                out.errorMessage = 'There is no comparison to show yet.';
                return out;
            }
            out.success = true;
            out.proposalId = ps[0].Id;
            out.comparisonJson = ps[0].Comparison_JSON__c;
        } catch (Exception e) {
            out.errorMessage = 'Could not load the comparison: ' + e.getMessage();
        }
        return out;
    }
}
