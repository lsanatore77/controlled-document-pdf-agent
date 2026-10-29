/**
 * Tests for the Screen Flow pieces (DocPdfFlowCreateAction). The create step itself is
 * covered by DocPdfAgentTest; this checks the flow action passes the proposal and the
 * decisions through and reports the result.
 */
@IsTest
private class DocPdfFlowTest {

    /** The running user with the app's permission set, as in DocPdfAgentTest (the queries run in user mode). */
    private static User appUser() {
        User me = new User(Id = UserInfo.getUserId());
        System.runAs(me) {
            List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'Doc_From_PDF_Agent_Access' LIMIT 1];
            if (!ps.isEmpty() && [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :me.Id AND PermissionSetId = :ps[0].Id
            ] == 0) {
                insert new PermissionSetAssignment(AssigneeId = me.Id, PermissionSetId = ps[0].Id);
            }
        }
        return me;
    }

    @IsTest
    static void stopsWhileAFieldIsUndecided() {
        System.runAs(appUser()) {
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review');
            insert p;
            insert new Doc_PDF_Field__c(
                Proposal__c = p.Id, Field_Label__c = 'Document Title', Field_API_Name__c = 'compliancequest__Title__c',
                Section__c = 'input', Field_Type__c = 'text', Required__c = true, Sort_Order__c = 1);
            DocPdfFlowCreateAction.Request req = new DocPdfFlowCreateAction.Request();
            req.proposalId = p.Id;
            req.decisionsJson = '[]';

            Test.startTest();
            List<DocPdfFlowCreateAction.Result> res = DocPdfFlowCreateAction.run(
                new List<DocPdfFlowCreateAction.Request>{ req });
            Test.stopTest();

            System.assertEquals(1, res.size());
            System.assertEquals(false, res[0].success, 'Nothing should be created while a field is undecided.');
            System.assertEquals(null, res[0].recordId);
            System.assertEquals(1, res[0].undecidedCount);
            System.assert(res[0].summary.contains('Document Title'), res[0].summary);
        }
    }

    @IsTest
    static void reportsAPreviouslyCreatedDocument() {
        System.runAs(appUser()) {
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(
                Status__c = 'Created', Created_Record_Id__c = UserInfo.getUserId(), Created_Record_Name__c = 'TEST-1');
            insert p;
            DocPdfFlowCreateAction.Request req = new DocPdfFlowCreateAction.Request();
            req.proposalId = p.Id;

            List<DocPdfFlowCreateAction.Result> res = DocPdfFlowCreateAction.run(
                new List<DocPdfFlowCreateAction.Request>{ req });

            System.assertEquals(true, res[0].success);
            System.assertEquals('TEST-1', res[0].documentName);
        }
    }

    @IsTest
    static void handlesAMissingRequest() {
        System.runAs(appUser()) {
            List<DocPdfFlowCreateAction.Result> res = DocPdfFlowCreateAction.run(
                new List<DocPdfFlowCreateAction.Request>{ null });
            System.assertEquals(false, res[0].success);
            System.assertEquals(0, res[0].undecidedCount);
        }
    }
}
