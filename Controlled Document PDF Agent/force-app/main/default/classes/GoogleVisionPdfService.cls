/**
 * GoogleVisionPdfService
 * ------------------------
 * Reads the text of a PDF with Google Cloud Vision, synchronously, so an agent
 * action (through the Doc_From_PDF_Analyze flow) gets the text back in the same call.
 *
 * - Vision's files:annotate call reads at most 5 pages per request, so this class
 *   sends one request per block of 5 pages until it has read the whole file
 *   (or reaches maxPages, the callout limit, or the time budget).
 * - Only the page text is requested (Google's "fields" response mask), which keeps
 *   the response small enough for the synchronous heap limit.
 * - The API key is NOT in this code. It comes from the Google_Cloud_Vision Named
 *   Credential: set Authentication to Password, put the API key in Password, untick
 *   "Generate Authorization Header" and tick "Allow Merge Fields in HTTP Header".
 *   The key is then sent as the X-Goog-Api-Key header.
 *
 * Make the callout before any DML in the same transaction.
 */
public with sharing class GoogleVisionPdfService {

    public static final String NAMED_CREDENTIAL = 'Google_Cloud_Vision';
    public static final Integer PAGES_PER_CALL = 5;
    /** Upper bound on pages read from one file. */
    public static Integer maxPages = 30;
    /** Total time budget for all Vision calls in one transaction (Apex allows 120 s). */
    @TestVisible
    private static Long timeBudgetMs = 110000;

    public class Extraction {
        public Boolean success = false;
        public String text = '';
        public Integer pagesRead = 0;
        public Integer totalPages = 0;
        public String fileName;
        public String message;
    }

    public static Extraction extract(Id contentVersionId) {
        Extraction ex = new Extraction();
        if (contentVersionId == null) {
            ex.message = 'No file was given.';
            return ex;
        }
        List<ContentVersion> cvs = [
            SELECT Id, Title, FileType, VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (cvs.isEmpty()) {
            ex.message = 'I could not open that file. It may have been deleted, or you may not have access to it.';
            return ex;
        }
        ContentVersion cv = cvs[0];
        ex.fileName = cv.Title;
        if (cv.FileType != 'PDF') {
            ex.message = 'That file is not a PDF (' + cv.FileType + ').';
            return ex;
        }

        String content = EncodingUtil.base64Encode(cv.VersionData);
        Long started = System.currentTimeMillis();
        List<String> pageTexts = new List<String>();
        Integer firstPage = 1;
        Integer total = null;

        while (true) {
            Integer lastPage = firstPage + PAGES_PER_CALL - 1;
            if (total != null && lastPage > total) {
                lastPage = total;
            }
            if (lastPage > maxPages) {
                lastPage = maxPages;
            }
            List<Integer> pages = new List<Integer>();
            for (Integer p = firstPage; p <= lastPage; p++) {
                pages.add(p);
            }
            if (pages.isEmpty()) {
                break;
            }

            Long remaining = timeBudgetMs - (System.currentTimeMillis() - started);
            if (remaining < 10000 || Limits.getCallouts() >= Limits.getLimitCallouts()) {
                break;
            }

            HttpResponse res;
            try {
                res = send(content, pages, Math.min(remaining, 120000L).intValue());
            } catch (Exception e) {
                ex.message = 'Google Vision could not be reached: ' + e.getMessage();
                break;
            }
            if (res.getStatusCode() != 200) {
                ex.message = describeError(res);
                break;
            }

            PageBlock block = parse(res.getBody());
            if (block.totalPages != null && block.totalPages > 0) {
                total = block.totalPages;
            }
            pageTexts.addAll(block.texts);
            ex.pagesRead += block.texts.size();

            firstPage = lastPage + 1;
            if (total == null || firstPage > total || firstPage > maxPages) {
                break;
            }
        }

        ex.totalPages = total == null ? ex.pagesRead : total;
        ex.text = String.join(pageTexts, '\n');
        ex.success = ex.pagesRead > 0 && String.isNotBlank(ex.text);
        if (ex.success && ex.pagesRead < ex.totalPages && String.isBlank(ex.message)) {
            ex.message = 'Read ' + ex.pagesRead + ' of ' + ex.totalPages + ' pages.';
        } else if (!ex.success && String.isBlank(ex.message)) {
            ex.message = 'Google Vision returned no text for this file.';
        }
        return ex;
    }

    private static HttpResponse send(String content, List<Integer> pages, Integer timeoutMs) {
        Map<String, Object> body = new Map<String, Object>{
            'requests' => new List<Object>{
                new Map<String, Object>{
                    'inputConfig' => new Map<String, Object>{
                        'mimeType' => 'application/pdf',
                        'content' => content
                    },
                    'features' => new List<Object>{
                        new Map<String, Object>{ 'type' => 'DOCUMENT_TEXT_DETECTION' }
                    },
                    'pages' => pages
                }
            }
        };
        String mask = EncodingUtil.urlEncode('responses(totalPages,responses(fullTextAnnotation(text),error))', 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + NAMED_CREDENTIAL + '/v1/files:annotate?fields=' + mask);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Goog-Api-Key', '{!$Credential.Password}');
        req.setBody(JSON.serialize(body));
        req.setTimeout(Math.max(1000, timeoutMs));
        return new Http().send(req);
    }

    @TestVisible
    private class PageBlock {
        Integer totalPages;
        List<String> texts = new List<String>();
    }

    @TestVisible
    private static PageBlock parse(String body) {
        PageBlock block = new PageBlock();
        Map<String, Object> root = (Map<String, Object>) System.JSON.deserializeUntyped(body);
        List<Object> fileResponses = (List<Object>) root.get('responses');
        if (fileResponses == null || fileResponses.isEmpty()) {
            return block;
        }
        Map<String, Object> fileResponse = (Map<String, Object>) fileResponses[0];
        Object tp = fileResponse.get('totalPages');
        if (tp != null) {
            block.totalPages = Integer.valueOf(tp);
        }
        List<Object> pageResponses = (List<Object>) fileResponse.get('responses');
        if (pageResponses == null) {
            return block;
        }
        for (Object o : pageResponses) {
            Map<String, Object> page = (Map<String, Object>) o;
            Map<String, Object> annotation = (Map<String, Object>) page.get('fullTextAnnotation');
            String t = annotation == null ? null : (String) annotation.get('text');
            block.texts.add(t == null ? '' : t);
        }
        return block;
    }

    @TestVisible
    private static String describeError(HttpResponse res) {
        Integer code = res.getStatusCode();
        String detail = '';
        try {
            Map<String, Object> root = (Map<String, Object>) System.JSON.deserializeUntyped(res.getBody());
            Map<String, Object> err = (Map<String, Object>) root.get('error');
            if (err != null && err.get('message') != null) {
                detail = ' ' + String.valueOf(err.get('message'));
            }
        } catch (Exception ignore) {
            detail = '';
        }
        if (code == 400 || code == 401 || code == 403) {
            return 'Google Vision rejected the request (' + code + ').' + detail +
                ' Check the API key on the Google_Cloud_Vision Named Credential (see the README).';
        }
        return 'Google Vision returned an error (' + code + ').' + detail;
    }
}
