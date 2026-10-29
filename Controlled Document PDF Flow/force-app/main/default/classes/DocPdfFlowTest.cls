/**
 * Tests for the Screen Flow pieces (DocPdfFlowCreateAction). The create step itself is
 * covered by DocPdfAgentTest; this checks the flow action passes the proposal and the
 * decisions through and reports the result.
 */
@IsTest
private class DocPdfFlowTest {

    @IsTest
    static void stopsWhileAFieldIsUndecided() {
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

    @IsTest
    static void reportsAPreviouslyCreatedDocument() {
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

    @IsTest
    static void handlesAMissingRequest() {
        List<DocPdfFlowCreateAction.Result> res = DocPdfFlowCreateAction.run(
            new List<DocPdfFlowCreateAction.Request>{ null });
        System.assertEquals(false, res[0].success);
        System.assertEquals(0, res[0].undecidedCount);
    }
}
