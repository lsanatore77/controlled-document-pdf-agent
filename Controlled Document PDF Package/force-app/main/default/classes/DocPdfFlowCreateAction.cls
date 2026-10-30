/**
 * DocPdfFlowCreateAction
 * ------------------------
 * Screen Flow action behind the review screen. Takes the Proposal Id and the user's
 * decisions (JSON from the docPdfFlowReview component) as plain text, and runs the same
 * create step the agent uses (DocPdfCreateDocumentAction): saves the decisions, stops with
 * a list if anything is still undecided, otherwise creates the Draft Controlled Document,
 * attaches the PDF as Primary Content and marks the proposal Created.
 */
public with sharing class DocPdfFlowCreateAction {

    public class Request {
        @InvocableVariable(label='Proposal Id' description='The Doc PDF Proposal being reviewed.' required=true)
        public String proposalId;
        @InvocableVariable(label='Decisions JSON' description='The user\'s decision on each field, from the review component. Optional.')
        public String decisionsJson;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Record Id') public String recordId;
        @InvocableVariable(label='Document Name' description='Document Number [Rev] of the new record.') public String documentName;
        @InvocableVariable(label='Summary' description='Plain-language result.') public String summary;
        @InvocableVariable(label='Undecided Count' description='Fields still needing a decision; nothing is created while this is above 0.') public Integer undecidedCount;
    }

    @InvocableMethod(
        label='Create Controlled Document from Reviewed PDF'
        description='Applies the user\'s field decisions and creates the Draft Controlled Document with the PDF as Primary Content.'
    )
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            DocPdfReview review = new DocPdfReview();
            review.proposalId = req == null ? null : req.proposalId;
            review.decisionsJson = req == null ? null : req.decisionsJson;
            DocPdfCreateDocumentAction.Request cr = new DocPdfCreateDocumentAction.Request();
            cr.review = review;
            DocPdfCreateDocumentAction.Result x = DocPdfCreateDocumentAction.run(
                new List<DocPdfCreateDocumentAction.Request>{ cr })[0];
            Result r = new Result();
            r.success = x.success == true;
            r.recordId = x.recordId;
            r.documentName = x.documentName;
            r.summary = x.summary;
            r.undecidedCount = x.undecidedCount == null ? 0 : x.undecidedCount;
            out.add(r);
        }
        return out;
    }
}
