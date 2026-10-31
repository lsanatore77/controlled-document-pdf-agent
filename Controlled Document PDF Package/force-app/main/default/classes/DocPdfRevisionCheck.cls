/**
 * DocPdfRevisionCheck
 * ---------------------
 * Before a new Controlled Document is created from a file: is the file really a new version of
 * a document that already exists? Runs when the review is built, with no callouts:
 *   1. Same number: a document number in the file (labelled, or in the header) or in the file
 *      name matches an existing Controlled Document.
 *   2. Same content: most of the text matches a file that was uploaded here before and used to
 *      create a document (the text kept on its Doc PDF Proposal), or whose text is cached.
 *   3. Same title: the title matches an existing document's title.
 * The best match is saved on the proposal (Controlled Document, Match Verdict, Match Score) and
 * the review shows it with Compare, Open to revise and Create anyway. Template Documents are never
 * matched. Nothing is changed on any Controlled Document.
 */
public with sharing class DocPdfRevisionCheck {

    public static final String SAME_NUMBER = 'Same number';
    public static final String SAME_CONTENT = 'Same content';
    public static final String SAME_TITLE = 'Same title';

    /** Below this % of shared text, content alone does not make a match. */
    public static Decimal contentMin = 60;
    /** % of title words in common (of the longer title) for a title-only match. */
    public static Decimal titleMin = 80;
    /** Earlier uploads checked for shared content when nothing else matches. */
    public static Integer recentUploads = 20;
    /** Stop the content scan past this CPU time (ms), so building the review never fails. */
    public static Integer cpuBudget = 4000;

    public class Found {
        public Id documentId;
        public String kind;
        public Decimal shared;
    }

    /** Tests set this instead of querying: the org's validation may block inserting documents. */
    @TestVisible
    private static List<compliancequest__SQX_Controlled_Document__c> testDocuments;
    /** Tests set this: earlier text by document Id. */
    @TestVisible
    private static Map<Id, String> testTexts;

    // ------------------------------------------------------------------ entry

    /** The existing document this file most likely revises, or null. Never throws. */
    public static Found check(String text, String fileName, String proposedTitle, Id proposalId) {
        try {
            if (String.isBlank(text)) {
                return null;
            }
            DocPdfMatchService.Settings st = DocPdfMatchService.loadSettings();
            Set<String> numbers = numbersIn(text, fileName, st);
            String title = String.isNotBlank(proposedTitle) ? proposedTitle
                : DocPdfFieldParser.labeledValue(text, st.titleLabel);

            List<compliancequest__SQX_Controlled_Document__c> docs = testDocuments != null
                ? testDocuments : candidates(numbers, title);
            Map<Id, String> texts = testTexts != null ? testTexts : earlierTexts(docs, proposalId);
            return pick(docs, text, numbers, title, texts);
        } catch (Exception e) {
            return null; // The check is a hint: it must never stop the review.
        }
    }

    // ------------------------------------------------------------------ decision

    @TestVisible
    private static Found pick(List<compliancequest__SQX_Controlled_Document__c> docs, String text,
                              Set<String> numbers, String title, Map<Id, String> texts) {
        Set<String> normNumbers = new Set<String>();
        for (String n : numbers) {
            normNumbers.add(norm(n));
        }
        Found best = null;
        Integer bestRank = 0;
        compliancequest__SQX_Controlled_Document__c bestDoc = null;
        for (compliancequest__SQX_Controlled_Document__c d : docs) {
            Integer rank = 0;
            String kind;
            Decimal shared;
            String earlier = d.Id == null ? null : texts.get(d.Id);
            if (String.isNotBlank(earlier) && Limits.getCpuTime() < cpuBudget) {
                shared = sharedPercent(earlier, text);
            }
            if (String.isNotBlank(d.compliancequest__Document_Number__c)
                && normNumbers.contains(norm(d.compliancequest__Document_Number__c))) {
                rank = 3;
                kind = SAME_NUMBER;
            } else if (shared != null && shared >= contentMin) {
                rank = 2;
                kind = SAME_CONTENT;
            } else if (titleMatches(title, d.compliancequest__Title__c)) {
                rank = 1;
                kind = SAME_TITLE;
            }
            if (rank == 0) {
                continue;
            }
            // Same rank: more shared text, then the Current one, then the newest.
            Boolean better = best == null || rank > bestRank
                || (rank == bestRank && nz(shared) > nz(best.shared))
                || (rank == bestRank && nz(shared) == nz(best.shared) && isCurrent(d) && !isCurrent(bestDoc));
            if (better) {
                best = new Found();
                best.documentId = d.Id;
                best.kind = kind;
                best.shared = shared;
                bestRank = rank;
                bestDoc = d;
            }
        }
        return best;
    }

    @TestVisible
    private static Boolean titleMatches(String a, String b) {
        if (String.isBlank(a) || String.isBlank(b)) {
            return false;
        }
        if (a.trim().equalsIgnoreCase(b.trim())) {
            return true;
        }
        Set<String> wa = words(a);
        Set<String> wb = words(b);
        if (wa.size() < 2 || wb.size() < 2) {
            return false;
        }
        Integer common = 0;
        for (String w : wa) {
            if (wb.contains(w)) {
                common++;
            }
        }
        return Decimal.valueOf(common) * 100 / Math.max(wa.size(), wb.size()) >= titleMin;
    }

    // ------------------------------------------------------------------ signals

    private static final Pattern NUMBER_TOKEN = Pattern.compile('\\b([A-Z][A-Z0-9]{1,9}-[0-9]{2,9})\\b');

    /** Document numbers in the file: the labelled one, any in the first lines, and any in the file name. */
    @TestVisible
    private static Set<String> numbersIn(String text, String fileName, DocPdfMatchService.Settings st) {
        Set<String> out = new Set<String>();
        String labelled = DocPdfFieldParser.labeledValue(text, st.numberLabel);
        if (String.isNotBlank(labelled)) {
            String n = labelled.trim().split(' ')[0];
            out.add(n.contains('[') ? n.substringBefore('[') : n);
        }
        for (String source : new List<String>{ text == null ? null : text.left(3000), fileName }) {
            if (String.isBlank(source)) {
                continue;
            }
            Matcher m = NUMBER_TOKEN.matcher(source.toUpperCase());
            while (m.find() && out.size() < 12) {
                out.add(m.group(1));
            }
        }
        out.remove(null);
        out.remove('');
        return out;
    }

    private static final Set<String> STOP = new Set<String>{
        'the', 'and', 'for', 'with', 'from', 'into', 'this', 'that', 'sop', 'procedure', 'document', 'policy',
        'work', 'instruction', 'standard', 'operating'
    };

    private static Set<String> words(String s) {
        Set<String> out = new Set<String>();
        for (String w : s.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').normalizeSpace().split(' ')) {
            if (w.length() >= 3 && !STOP.contains(w)) {
                out.add(w);
            }
        }
        return out;
    }

    /** % of the shorter text's 5-word phrases also in the other (as DocPdfMatchService counts them). */
    @TestVisible
    private static Decimal sharedPercent(String a, String b) {
        Set<String> sa = shingles(a);
        Set<String> sb = shingles(b);
        if (sa.isEmpty() || sb.isEmpty()) {
            return 0;
        }
        Set<String> small = sa.size() <= sb.size() ? sa : sb;
        Set<String> big = sa.size() <= sb.size() ? sb : sa;
        Integer common = 0;
        for (String x : small) {
            if (big.contains(x)) {
                common++;
            }
        }
        return (Decimal.valueOf(common) * 100 / small.size()).setScale(1);
    }

    private static Set<String> shingles(String text) {
        List<String> ws = new List<String>();
        for (String l : DocPdfFieldParser.cleanLinesOf(text)) {
            if (DocPdfFieldParser.isRepeatedHeader(l) || DocPdfFieldParser.isContentsLine(l)
                || Pattern.matches('(?i)^page \\d+( of \\d+)?$', l)) {
                continue;
            }
            for (String w : l.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').normalizeSpace().split(' ')) {
                if (String.isNotBlank(w)) {
                    ws.add(w);
                }
            }
        }
        Set<String> out = new Set<String>();
        for (Integer i = 0; i + 5 <= ws.size() && out.size() < 20000; i++) {
            out.add(ws[i] + ' ' + ws[i + 1] + ' ' + ws[i + 2] + ' ' + ws[i + 3] + ' ' + ws[i + 4]);
        }
        return out;
    }

    private static String norm(String n) {
        return n == null ? '' : n.toUpperCase().replaceAll('\\[.*\\]', '').replaceAll('[^A-Z0-9]', '');
    }

    private static Decimal nz(Decimal d) {
        return d == null ? 0 : d;
    }

    private static Boolean isCurrent(compliancequest__SQX_Controlled_Document__c d) {
        return d != null && d.compliancequest__Document_Status__c == 'Current';
    }

    // ------------------------------------------------------------------ lookups

    /** Documents (not templates) with one of the numbers, a similar title, or made from an earlier upload. */
    private static List<compliancequest__SQX_Controlled_Document__c> candidates(Set<String> numbers, String title) {
        Map<Id, compliancequest__SQX_Controlled_Document__c> out = new Map<Id, compliancequest__SQX_Controlled_Document__c>();
        Id templateType = templateTypeId();
        if (!numbers.isEmpty()) {
            out.putAll(new Map<Id, compliancequest__SQX_Controlled_Document__c>([
                SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                       compliancequest__Document_Status__c, compliancequest__Content_Reference__c, RecordTypeId
                FROM compliancequest__SQX_Controlled_Document__c
                WHERE compliancequest__Document_Number__c IN :numbers
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50
            ]));
        }
        String key = longestWord(title);
        if (key != null) {
            String likeValue = '%' + key + '%';
            out.putAll(new Map<Id, compliancequest__SQX_Controlled_Document__c>([
                SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                       compliancequest__Document_Status__c, compliancequest__Content_Reference__c, RecordTypeId
                FROM compliancequest__SQX_Controlled_Document__c
                WHERE compliancequest__Title__c LIKE :likeValue
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50
            ]));
        }
        Set<Id> fromUploads = new Set<Id>();
        for (Doc_PDF_Proposal__c p : [
            SELECT Created_Record_Id__c FROM Doc_PDF_Proposal__c
            WHERE Status__c = 'Created' AND Created_Record_Id__c != null
            WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT :recentUploads
        ]) {
            Id did = toId(p.Created_Record_Id__c);
            if (did != null && !out.containsKey(did)) {
                fromUploads.add(did);
            }
        }
        if (!fromUploads.isEmpty()) {
            out.putAll(new Map<Id, compliancequest__SQX_Controlled_Document__c>([
                SELECT Id, Name, compliancequest__Document_Number__c, compliancequest__Title__c,
                       compliancequest__Document_Status__c, compliancequest__Content_Reference__c, RecordTypeId
                FROM compliancequest__SQX_Controlled_Document__c
                WHERE Id IN :fromUploads
                WITH USER_MODE
            ]));
        }
        List<compliancequest__SQX_Controlled_Document__c> kept = new List<compliancequest__SQX_Controlled_Document__c>();
        for (compliancequest__SQX_Controlled_Document__c d : out.values()) {
            if (templateType == null || d.RecordTypeId != templateType) {
                kept.add(d);
            }
        }
        return kept;
    }

    /** Text of each document from earlier: the upload it was created from, else its cached Primary Content text. */
    private static Map<Id, String> earlierTexts(List<compliancequest__SQX_Controlled_Document__c> docs, Id proposalId) {
        Map<Id, String> out = new Map<Id, String>();
        if (docs.isEmpty()) {
            return out;
        }
        Set<String> idStrings = new Set<String>();
        Set<String> contentDocIds = new Set<String>();
        Map<String, Id> docByContent = new Map<String, Id>();
        for (compliancequest__SQX_Controlled_Document__c d : docs) {
            idStrings.add(String.valueOf(d.Id));
            idStrings.add(String.valueOf(d.Id).left(15));
            if (String.isNotBlank(d.compliancequest__Content_Reference__c)) {
                contentDocIds.add(d.compliancequest__Content_Reference__c.trim());
                docByContent.put(d.compliancequest__Content_Reference__c.trim(), d.Id);
            }
        }
        for (Doc_PDF_Proposal__c p : [
            SELECT Created_Record_Id__c, Extracted_Text__c FROM Doc_PDF_Proposal__c
            WHERE Created_Record_Id__c IN :idStrings AND Id != :proposalId
            WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 50
        ]) {
            Id did = toId(p.Created_Record_Id__c);
            if (did != null && !out.containsKey(did) && String.isNotBlank(p.Extracted_Text__c)) {
                out.put(did, p.Extracted_Text__c);
            }
        }
        if (!contentDocIds.isEmpty()) {
            Map<String, Id> docByVersion = new Map<String, Id>();
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIds AND IsLatest = true
                WITH USER_MODE LIMIT 50
            ]) {
                Id did = docByContent.get(String.valueOf(cv.ContentDocumentId));
                if (did == null) {
                    did = docByContent.get(String.valueOf(cv.ContentDocumentId).left(15));
                }
                if (did != null && !out.containsKey(did)) {
                    docByVersion.put(String.valueOf(cv.Id), did);
                }
            }
            if (!docByVersion.isEmpty()) {
                for (Doc_PDF_Text_Cache__c c : [
                    SELECT Content_Version_Id__c, Text__c FROM Doc_PDF_Text_Cache__c
                    WHERE Content_Version_Id__c IN :docByVersion.keySet()
                    WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50
                ]) {
                    Id did = docByVersion.get(c.Content_Version_Id__c);
                    if (did != null && !out.containsKey(did)) {
                        out.put(did, c.Text__c);
                    }
                }
            }
        }
        return out;
    }

    private static Id templateTypeId() {
        Schema.RecordTypeInfo rt = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Template_Document');
        return rt == null ? null : rt.getRecordTypeId();
    }

    @TestVisible
    private static String longestWord(String title) {
        if (String.isBlank(title)) {
            return null;
        }
        String best = null;
        for (String w : words(title)) {
            if (best == null || w.length() > best.length()) {
                best = w;
            }
        }
        return best != null && best.length() >= 4 ? best : null;
    }

    private static Id toId(String s) {
        try {
            Id i = Id.valueOf(s.trim());
            return i.getSobjectType() == compliancequest__SQX_Controlled_Document__c.SObjectType ? i : null;
        } catch (Exception e) {
            return null;
        }
    }
}
