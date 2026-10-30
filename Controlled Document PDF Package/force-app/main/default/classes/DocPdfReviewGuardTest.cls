/**
 * Tests for the safety net in DocPdfSelectFileAction: a review submit sent to
 * Select PDF by mistake points back to the open review and never starts a new proposal.
 */
@IsTest
private class DocPdfReviewGuardTest {

    @IsTest
    static void reviewSubmitSentToSelectDoesNotStartOver() {
        Doc_PDF_Proposal__c open = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review', File_Name__c = 'Open Review');
        insert open;
        Integer before = [SELECT COUNT() FROM Doc_PDF_Proposal__c];

        // A review submit (proposal Id, no file) sent to Select PDF by mistake.
        DocPdfFileSelection s = new DocPdfFileSelection();
        s.proposalId = open.Id;
        DocPdfSelectFileAction.Result r = DocPdfSelectFileAction.runOne(s);
        Assert.isFalse(r.success);
        Assert.isTrue(r.reviewPending);
        Assert.areEqual((String) open.Id, r.proposalId);
        Assert.isTrue(r.message.contains('Open Review'), '' + r.message);

        // No value at all and no new file chosen: points back to the open review.
        DocPdfSelectFileAction.Result empty = DocPdfSelectFileAction.runOne(null);
        Assert.isTrue(empty.reviewPending, '' + empty.message);
        Assert.areEqual((String) open.Id, empty.proposalId);

        Assert.isNull(DocPdfSelectFileAction.awaitingReview('not-an-id'));
        Assert.areEqual(before, [SELECT COUNT() FROM Doc_PDF_Proposal__c], 'No new proposal is started');

        DocPdfReview review = new DocPdfReview();
        review.component = 'review';
        Assert.areEqual('review', review.component);
    }

    @IsTest
    static void nothingOpenStillAsksForAFile() {
        DocPdfSelectFileAction.Result r = DocPdfSelectFileAction.runOne(new DocPdfFileSelection());
        Assert.isFalse(r.success);
        Assert.isFalse(r.reviewPending);
        Assert.isTrue(r.message.startsWith('No file was chosen'), '' + r.message);
    }
}
