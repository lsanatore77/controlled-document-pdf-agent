/**
 * DocPdfMatchService
 * --------------------
 * Decides whether an uploaded PDF is a version of an existing Controlled Document or a
 * different document, before any comparison is shown. Rules only, no AI, so the result is
 * repeatable and its reasons can be shown to the user.
 *
 * Signals: document number (PDF label vs the record), title words, revision, section
 * headings, and the share of 5-word phrases the two texts have in common.
 *
 *   number same,    shared >= Version min            -> Version
 *   number same,    shared <  Version min            -> Rewritten (same document, heavily changed)
 *   number missing, shared >= Likely min, title ok   -> Likely Version
 *   number missing, shared >= Related min            -> Possibly Related (user may compare anyway)
 *   number differs, or shared below Related min      -> Different
 *
 * Cut-offs and PDF labels come from the Doc PDF Agent Setting custom metadata (record Default).
 */
public with sharing class DocPdfMatchService {

    public static final String VERSION = 'Version';
    public static final String REWRITTEN = 'Rewritten';
    public static final String LIKELY_VERSION = 'Likely Version';
    public static final String POSSIBLY_RELATED = 'Possibly Related';
    public static final String DIFFERENT = 'Different';

    public class Settings {
        public Decimal versionMin = 40;
        public Decimal likelyMin = 60;
        public Decimal relatedMin = 25;
        public Decimal titleMin = 60;
        public String numberLabel = 'Document Number';
        public String titleLabel = 'Title';
        public String revisionLabel = 'Revision';
        public String promptTemplate;
    }

    /** One reason shown under the verdict: kind ok | info | warn | bad, a short mark and a sentence. */
    public class Reason {
        public String kind;
        public String mark;
        public String text;
        public Reason(String kind, String mark, String text) {
            this.kind = kind;
            this.mark = mark;
            this.text = text;
        }
    }

    public class Result {
        public String verdict;
        public String title;
        public String text;
        public String tone;            // ok | warn | bad
        public Decimal shared = 0;     // % of 5-word phrases in common
        public Decimal titleMatch = 0; // % of title words in common
        public Decimal headingMatch = 0;
        public String numberState;     // same | different | missing
        public String pdfNumber;
        public String pdfTitle;
        public String pdfRevision;
        public String revisionDirection; // higher | same | lower | unknown
        public List<Reason> reasons = new List<Reason>();
        public Boolean compareByDefault = false;
    }

    @TestVisible
    private static Settings testSettings;

    public static Settings loadSettings() {
        if (testSettings != null) {
            return testSettings;
        }
        Settings st = new Settings();
        Doc_PDF_Agent_Setting__mdt m = Doc_PDF_Agent_Setting__mdt.getInstance('Default');
        if (m == null) {
            return st;
        }
        if (m.Version_Min_Shared__c != null) { st.versionMin = m.Version_Min_Shared__c; }
        if (m.Likely_Version_Min_Shared__c != null) { st.likelyMin = m.Likely_Version_Min_Shared__c; }
        if (m.Related_Min_Shared__c != null) { st.relatedMin = m.Related_Min_Shared__c; }
        if (m.Title_Match_Min__c != null) { st.titleMin = m.Title_Match_Min__c; }
        if (String.isNotBlank(m.Number_Label__c)) { st.numberLabel = m.Number_Label__c; }
        if (String.isNotBlank(m.Title_Label__c)) { st.titleLabel = m.Title_Label__c; }
        if (String.isNotBlank(m.Revision_Label__c)) { st.revisionLabel = m.Revision_Label__c; }
        st.promptTemplate = m.Summary_Prompt_Template__c;
        return st;
    }

    /**
     * docName: the record Name (e.g. SOP-44123[002]); docNumber, docTitle, docRevision: its field values.
     * oldText: text of its Primary Content; newText: text of the uploaded PDF.
     */
    public static Result match(String docName, String docNumber, String docTitle, String docRevision,
                               String oldText, String newText, Settings st) {
        Result r = new Result();
        String shownName = String.isNotBlank(docName) ? docName : nvl(docNumber, 'this document');

        r.pdfNumber = firstToken(DocPdfFieldParser.labeledValue(newText, st.numberLabel));
        r.pdfTitle = DocPdfFieldParser.labeledValue(newText, st.titleLabel);
        r.pdfRevision = firstToken(DocPdfFieldParser.labeledValue(newText, st.revisionLabel));
        String recordNumber = String.isNotBlank(docNumber) ? docNumber
            : firstToken(DocPdfFieldParser.labeledValue(oldText, st.numberLabel));
        String recordTitle = String.isNotBlank(docTitle) ? docTitle : DocPdfFieldParser.labeledValue(oldText, st.titleLabel);
        String recordRevision = String.isNotBlank(docRevision) ? docRevision
            : firstToken(DocPdfFieldParser.labeledValue(oldText, st.revisionLabel));

        // ---- signals
        if (String.isBlank(r.pdfNumber) || String.isBlank(recordNumber)) {
            r.numberState = 'missing';
        } else {
            r.numberState = normNumber(r.pdfNumber) == normNumber(recordNumber) ? 'same' : 'different';
        }
        r.titleMatch = String.isBlank(r.pdfTitle) || String.isBlank(recordTitle) ? Decimal.valueOf(0) : wordOverlap(r.pdfTitle, recordTitle);
        r.shared = sharedPercent(oldText, newText);
        r.headingMatch = headingOverlap(oldText, newText);
        r.revisionDirection = compareRevisions(r.pdfRevision, recordRevision);
        Boolean titleOk = r.titleMatch >= st.titleMin;

        // ---- reasons
        if (r.numberState == 'same') {
            r.reasons.add(new Reason('ok', 'Match', 'Document number matches (' + r.pdfNumber + ')'));
        } else if (r.numberState == 'different') {
            r.reasons.add(new Reason('bad', 'Differs', 'Document number in the PDF is ' + r.pdfNumber));
        } else {
            r.reasons.add(new Reason('warn', 'Missing', String.isBlank(r.pdfNumber)
                ? 'No document number in the PDF' : 'This document has no number to check against'));
        }
        if (String.isBlank(r.pdfTitle)) {
            r.reasons.add(new Reason('warn', 'Missing', 'No title in the PDF'));
        } else if (titleOk) {
            r.reasons.add(new Reason('ok', 'Match', r.titleMatch >= 100 ? 'Title matches' : 'Title mostly matches (' + r.titleMatch.setScale(0) + '% of words)'));
        } else if (r.titleMatch > 0) {
            r.reasons.add(new Reason('warn', 'Partial', 'Title partly matches (' + r.titleMatch.setScale(0) + '% of words)'));
        } else {
            r.reasons.add(new Reason('bad', 'Differs', 'Title is ' + r.pdfTitle.left(80)));
        }
        String sharedKind = r.shared >= st.versionMin ? 'ok' : (r.shared >= st.relatedMin ? 'warn' : 'bad');
        r.reasons.add(new Reason(sharedKind, r.shared.setScale(0) + '%', 'of the text is shared'));
        if (r.revisionDirection == 'higher') {
            r.reasons.add(new Reason('info', 'Higher', 'Revision ' + r.pdfRevision + ' is newer than ' + recordRevision));
        } else if (r.revisionDirection == 'same') {
            r.reasons.add(new Reason('warn', 'Same', 'Same revision (' + r.pdfRevision + '): this may be a duplicate'));
        } else if (r.revisionDirection == 'lower') {
            r.reasons.add(new Reason('warn', 'Lower', 'Revision ' + r.pdfRevision + ' is older than ' + recordRevision));
        } else if (String.isBlank(r.pdfRevision)) {
            r.reasons.add(new Reason('warn', 'Missing', 'No revision in the PDF'));
        }

        // ---- verdict
        if (r.numberState == 'same') {
            r.verdict = r.shared >= st.versionMin ? VERSION : REWRITTEN;
        } else if (r.numberState == 'different') {
            r.verdict = DIFFERENT;
        } else if (r.shared >= st.likelyMin && titleOk) {
            r.verdict = LIKELY_VERSION;
        } else if (r.shared >= st.relatedMin) {
            r.verdict = POSSIBLY_RELATED;
        } else {
            r.verdict = DIFFERENT;
        }
        r.compareByDefault = r.verdict == VERSION || r.verdict == REWRITTEN || r.verdict == LIKELY_VERSION;

        String age = r.revisionDirection == 'higher' ? 'Newer version'
            : r.revisionDirection == 'lower' ? 'Older version'
            : r.revisionDirection == 'same' ? 'Same revision' : 'Version';
        String revisionNote = String.isNotBlank(r.pdfRevision) && String.isNotBlank(recordRevision)
            ? 'Revision ' + recordRevision + ' → ' + r.pdfRevision + '. ' : '';
        if (r.verdict == VERSION) {
            r.title = age + ' of ' + shownName;
            r.text = revisionNote + 'Compared with the current Primary Content.';
            r.tone = r.revisionDirection == 'higher' || r.revisionDirection == 'unknown' ? 'ok' : 'warn';
        } else if (r.verdict == REWRITTEN) {
            r.title = 'Same document, heavily rewritten';
            r.text = revisionNote + 'The number matches ' + shownName + ', but only ' + r.shared.setScale(0) + '% of the text is shared.';
            r.tone = 'warn';
        } else if (r.verdict == LIKELY_VERSION) {
            r.title = 'Likely a version of ' + shownName;
            r.text = 'The PDF has no document number, so this could not be confirmed.';
            r.tone = 'warn';
        } else if (r.verdict == POSSIBLY_RELATED) {
            r.title = 'Possibly related';
            r.text = 'I can\'t confirm this is a version of ' + shownName + '. Compare anyway?';
            r.tone = 'warn';
        } else {
            r.title = 'Not a version of ' + shownName;
            r.text = 'This looks like a different document, so I didn\'t compare them.';
            r.tone = 'bad';
        }
        return r;
    }

    // ------------------------------------------------------------------ signals

    @TestVisible
    private static String normNumber(String n) {
        return n == null ? '' : n.toUpperCase().replaceAll('\\[.*\\]', '').replaceAll('[^A-Z0-9]', '');
    }

    private static final Set<String> STOP = new Set<String>{
        'the', 'and', 'for', 'with', 'from', 'into', 'this', 'that', 'sop', 'procedure', 'document'
    };

    @TestVisible
    private static Set<String> words(String s) {
        Set<String> out = new Set<String>();
        if (String.isBlank(s)) {
            return out;
        }
        for (String w : s.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').split(' ')) {
            if (w.length() >= 3 && !STOP.contains(w)) {
                out.add(w);
            }
        }
        return out;
    }

    /** % of the smaller title's words found in the other title. */
    @TestVisible
    private static Decimal wordOverlap(String a, String b) {
        Set<String> wa = words(a);
        Set<String> wb = words(b);
        if (wa.isEmpty() || wb.isEmpty()) {
            return 0;
        }
        Integer common = 0;
        for (String w : wa) {
            if (wb.contains(w)) {
                common++;
            }
        }
        return (Decimal.valueOf(common) * 100 / Math.min(wa.size(), wb.size())).setScale(1);
    }

    /** Body text as normalized words, without repeated page headers and contents lines. */
    @TestVisible
    private static List<String> bodyWords(String text) {
        List<String> out = new List<String>();
        for (String l : DocPdfFieldParser.cleanLinesOf(text)) {
            if (DocPdfFieldParser.isRepeatedHeader(l) || DocPdfFieldParser.isContentsLine(l)
                || Pattern.matches('(?i)^page \\d+( of \\d+)?$', l)) {
                continue;
            }
            for (String w : l.toLowerCase().replaceAll('[^a-z0-9 ]', ' ').normalizeSpace().split(' ')) {
                if (String.isNotBlank(w)) {
                    out.add(w);
                }
            }
        }
        return out;
    }

    private static Set<String> shingles(List<String> ws) {
        Set<String> out = new Set<String>();
        for (Integer i = 0; i + 5 <= ws.size() && out.size() < 20000; i++) {
            out.add(ws[i] + ' ' + ws[i + 1] + ' ' + ws[i + 2] + ' ' + ws[i + 3] + ' ' + ws[i + 4]);
        }
        return out;
    }

    /** % of the shorter text's 5-word phrases that also appear in the other text. */
    @TestVisible
    private static Decimal sharedPercent(String oldText, String newText) {
        Set<String> a = shingles(bodyWords(oldText));
        Set<String> b = shingles(bodyWords(newText));
        if (a.isEmpty() || b.isEmpty()) {
            return 0;
        }
        Set<String> small = a.size() <= b.size() ? a : b;
        Set<String> big = a.size() <= b.size() ? b : a;
        Integer common = 0;
        for (String x : small) {
            if (big.contains(x)) {
                common++;
            }
        }
        return (Decimal.valueOf(common) * 100 / small.size()).setScale(1);
    }

    @TestVisible
    private static Decimal headingOverlap(String oldText, String newText) {
        Set<String> a = new Set<String>();
        for (DocPdfCompareService.Section sec : DocPdfCompareService.sections(oldText)) {
            a.add(sec.key);
        }
        Set<String> b = new Set<String>();
        for (DocPdfCompareService.Section sec : DocPdfCompareService.sections(newText)) {
            b.add(sec.key);
        }
        a.remove(DocPdfCompareService.FRONT_KEY);
        b.remove(DocPdfCompareService.FRONT_KEY);
        if (a.isEmpty() || b.isEmpty()) {
            return 0;
        }
        Integer common = 0;
        for (String k : a) {
            if (b.contains(k)) {
                common++;
            }
        }
        Set<String> all = new Set<String>(a);
        all.addAll(b);
        return (Decimal.valueOf(common) * 100 / all.size()).setScale(1);
    }

    /** higher | same | lower | unknown: the PDF's revision compared with the record's. */
    @TestVisible
    private static String compareRevisions(String pdfRevision, String recordRevision) {
        if (String.isBlank(pdfRevision) || String.isBlank(recordRevision)) {
            return 'unknown';
        }
        String a = pdfRevision.trim().toUpperCase();
        String b = recordRevision.trim().toUpperCase();
        Integer c;
        if (a.isNumeric() && b.isNumeric()) {
            Long x = Long.valueOf(a);
            Long y = Long.valueOf(b);
            c = x == y ? 0 : (x > y ? 1 : -1);
        } else {
            c = a.compareTo(b);
        }
        return c == 0 ? 'same' : (c > 0 ? 'higher' : 'lower');
    }

    private static String firstToken(String v) {
        return String.isBlank(v) ? null : v.trim().split(' ')[0];
    }

    private static String nvl(String s, String fallback) {
        return String.isBlank(s) ? fallback : s;
    }
}
