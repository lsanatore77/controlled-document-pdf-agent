/**
 * ExtractPdfTextSyncAction
 * --------------------------
 * Flow / agent action that returns the text of a PDF in the same call
 * (GoogleVisionPdfService). Used by the Doc_From_PDF_Analyze flow as its first
 * step, before any record is written.
 *
 * The existing ExtractPdfTextVisionAction and GoogleVisionPdfQueueable are not
 * changed; they still run in the background and write the text to a field.
 */
public with sharing class ExtractPdfTextSyncAction {

    public class Request {
        @InvocableVariable(label='Content Version Id' description='The ContentVersion Id of the PDF.' required=true)
        public String contentVersionId;
    }

    public class Result {
        @InvocableVariable(label='Success' description='True when text was read from at least one page.')
        public Boolean success;
        @InvocableVariable(label='Extracted Text' description='Text of the pages that were read, in page order.')
        public String extractedText;
        @InvocableVariable(label='Pages Read')
        public Integer pagesRead;
        @InvocableVariable(label='Total Pages')
        public Integer totalPages;
        @InvocableVariable(label='Message' description='Plain-language problem or note, if any.')
        public String message;
    }

    @InvocableMethod(
        label='Extract PDF Text Now (Google Vision)'
        description='Reads the text of a PDF (Google Cloud Vision, 5 pages per request) or a Word .docx file (read in Apex) and returns it in the same call.'
        callout=true
    )
    public static List<Result> run(List<Request> requests) {
        List<Result> out = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                Id cvId = String.isBlank(req.contentVersionId) ? null : Id.valueOf(req.contentVersionId.trim());
                GoogleVisionPdfService.Extraction ex = GoogleVisionPdfService.extract(cvId);
                r.success = ex.success;
                r.extractedText = ex.text;
                r.pagesRead = ex.pagesRead;
                r.totalPages = ex.totalPages;
                r.message = ex.message;
            } catch (Exception e) {
                r.success = false;
                r.extractedText = '';
                r.pagesRead = 0;
                r.totalPages = 0;
                r.message = 'The file could not be read: ' + e.getMessage();
            }
            out.add(r);
        }
        return out;
    }
}
