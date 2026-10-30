/**
 * DocPdfBuildRecommendationsAction
 * ----------------------------------
 * Second step of the Doc_From_PDF_Analyze flow: takes the text from
 * ExtractPdfTextSyncAction and stores one recommendation row per field on the
 * proposal (DocPdfRecommendationBuilder). Writes records, so it must run after
 * the Google Vision callout.
 */
public with sharing class DocPdfBuildRecommendationsAction {

    public class Request {
        @InvocableVariable(label='Proposal Id' required=true)
        public String proposalId;
        @InvocableVariable(label='Extracted Text')
        public String extractedText;
        @InvocableVariable(label='Pages Read')
        public Integer pagesRead;
        @InvocableVariable(label='Total Pages')
        public Integer totalPages;
        @InvocableVariable(label='Extraction Succeeded')
        public Boolean extractionSucceeded;
        @InvocableVariable(label='Extraction Message')
        public String extractionMessage;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Summary' description='Plain-language result to relay to the user.') public String summary;
        @InvocableVariable(label='Ready Count') public Integer readyCount;
        @InvocableVariable(label='Needs Review Count') public Integer reviewCount;
        @InvocableVariable(label='Needs Input Count') public Integer inputCount;
        @InvocableVariable(label='Related Records Count') public Integer relatedCount;
    }

    @InvocableMethod(
        label='Build Field Recommendations from PDF Text'
        description='Stores a recommended value for each Controlled Document field, from the text of the PDF, for the user to review.'
    )
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            if (String.isBlank(req.proposalId)) {
                r.success = false;
                r.summary = 'No PDF has been chosen yet. Upload a PDF or pick one from the list first.';
                r.readyCount = 0;
                r.reviewCount = 0;
                r.inputCount = 0;
                r.relatedCount = 0;
                out.add(r);
                continue;
            }
            try {
                DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(
                    Id.valueOf(req.proposalId.trim()), req.extractedText, req.pagesRead, req.totalPages,
                    req.extractionSucceeded, req.extractionMessage);
                r.success = s.success;
                r.summary = s.message;
                r.readyCount = s.readyCount;
                r.reviewCount = s.reviewCount;
                r.inputCount = s.inputCount;
                r.relatedCount = s.relatedCount;
            } catch (Exception e) {
                r.success = false;
                r.summary = 'I could not prepare the field recommendations: ' + e.getMessage();
                r.readyCount = 0;
                r.reviewCount = 0;
                r.inputCount = 0;
                r.relatedCount = 0;
            }
            out.add(r);
        }
        return out;
    }
}
