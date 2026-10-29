/**
 * DocPdfFieldParser
 * -------------------
 * Turns the plain text of a ComplianceQuest-style SOP PDF into labelled values.
 * Label based, so it works on the text from Google Vision or any other reader:
 *
 *   Page header : Document Number, Revision, Title, Department, Effective Date
 *   Last page   : Author, Document Category, Document Status, Date Approved,
 *                 Expiration Date, Revision History, Related Documents, Requirements
 *   Body        : 1. Purpose (for Description), Key Updates (for Changes / Change Scope)
 *
 * The first value found for each label wins (the header repeats on every page).
 * Nothing here queries or writes records.
 */
public with sharing class DocPdfFieldParser {

    public class Parsed {
        public String documentNumber;
        public String revision;
        public String title;
        public String department;
        public String effectiveDate;      // yyyy-MM-dd
        public String effectiveDateRaw;
        public String author;
        public String documentCategory;
        public String documentStatus;
        public String dateApproved;       // yyyy-MM-dd
        public String dateApprovedRaw;
        public String expirationDate;     // yyyy-MM-dd
        public String purpose;            // whole Purpose section
        public String purposeSummary;     // its first sentence
        public List<String> keyUpdateHeadings = new List<String>();
        public List<String> changeMarkers = new List<String>();
        public Boolean hasMajorMarkers = false;
        public List<String> relatedDocumentNumbers = new List<String>();
        public List<String> jobFunctions = new List<String>();
        public List<String> revisions = new List<String>();
    }

    private static final Set<String> SECTION_STOPS = new Set<String>{
        'approval history', 'revision history', 'related documents', 'requirements'
    };
    private static final Set<String> TABLE_HEADERS = new Set<String>{
        'job function', 'description', 'effective date', 'document number', 'title',
        'step', 'name of approver', 'approval date', 'revision number', 'changes'
    };
    private static final List<String> MAJOR_MARKERS = new List<String>{
        'new requirement', 'new procedure', 'new step', 'new testing requirement'
    };
    private static final List<String> ALL_MARKERS = new List<String>{
        'new requirement', 'new procedure', 'new step', 'new testing requirement',
        'new guidance', 'new instruction', 'updated instructions', 'expanded section',
        'expanded record-keeping'
    };
    private static final Map<String, Integer> MONTHS = new Map<String, Integer>{
        'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
        'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12
    };

    public static Parsed parse(String text) {
        Parsed p = new Parsed();
        if (String.isBlank(text)) {
            return p;
        }
        List<String> lines = cleanLines(text);

        p.documentNumber = firstToken(labelValue(lines, 'Document Number'));
        p.revision = firstToken(labelValue(lines, 'Revision'));
        p.title = labelValue(lines, 'Title');
        p.department = labelValue(lines, 'Department');
        p.effectiveDateRaw = labelValue(lines, 'Effective Date');
        p.effectiveDate = toIsoDate(p.effectiveDateRaw);
        p.author = labelValue(lines, 'Author');
        p.documentCategory = labelValue(lines, 'Document Category');
        p.documentStatus = labelValue(lines, 'Document Status');
        p.dateApprovedRaw = labelValue(lines, 'Date Approved');
        p.dateApproved = toIsoDate(p.dateApprovedRaw);
        p.expirationDate = toIsoDate(labelValue(lines, 'Expiration Date'));

        readPurpose(lines, p);
        readKeyUpdates(lines, p);
        readRelatedDocuments(lines, p);
        readRequirements(lines, p);
        readRevisions(lines, p);
        return p;
    }

    // ---------------------------------------------------------------- generic lookups (field config)

    /** The value after "Label:" in the PDF text (same line or the next line), or null. */
    public static String labeledValue(String text, String label) {
        if (String.isBlank(text) || String.isBlank(label)) {
            return null;
        }
        return labelValue(cleanLines(text), label.trim().removeEnd(':'));
    }

    /** First sentence of a block of text, at most maxLen characters, or null. */
    public static String firstSentenceOf(String s, Integer maxLen) {
        return firstSentence(s, maxLen);
    }

    /** 13-Nov-2024, 13 Nov 2024, 2024-11-13 or 11/13/2024 as yyyy-MM-dd, or null. */
    public static String isoDate(String raw) {
        return toIsoDate(raw);
    }

    /** The PDF text as clean lines: blank lines, watermark letters and copyright footers removed. */
    public static List<String> cleanLinesOf(String text) {
        return String.isBlank(text) ? new List<String>() : cleanLines(text);
    }

    /** True for a line repeated at the top of every page (Document Number:, Revision:, Title:, ...). */
    public static Boolean isRepeatedHeader(String line) {
        return line != null && isPageHeader(line);
    }

    /** True for a table-of-contents line ("1. Purpose.......3"). */
    public static Boolean isContentsLine(String line) {
        return line != null && isTocLine(line);
    }

    private static final Set<String> COMMON_HEADINGS = new Set<String>{
        'purpose', 'scope', 'key updates', 'responsibilities', 'definitions', 'procedure', 'references',
        'related documents', 'requirements', 'revision history', 'approval history', 'table of contents'
    };

    /**
     * The text of the section whose heading is the given name ("Purpose" also matches
     * "1. Purpose" and "1 Purpose:"), up to the next heading. Table-of-contents lines and
     * repeated page headers are skipped. Null when there is no such section.
     */
    public static String sectionText(String text, String heading) {
        if (String.isBlank(text) || String.isBlank(heading)) {
            return null;
        }
        List<String> lines = cleanLines(text);
        String name = heading.trim().removeEnd(':');
        Integer start = findHeading(lines, '(?i)^(\\d+\\.?\\s*)?' + Pattern.quote(name) + '\\s*:?\\s*$', 0);
        if (start < 0) {
            return null;
        }
        List<String> parts = new List<String>();
        for (Integer i = start + 1; i < lines.size() && parts.size() < 60; i++) {
            String l = lines[i];
            String bare = l.replaceFirst('^\\d+\\.?\\s*', '').removeEnd(':').trim().toLowerCase();
            if (COMMON_HEADINGS.contains(bare) || Pattern.matches('^\\d+\\.?\\s+[A-Z][A-Za-z ]{2,40}$', l)) {
                break;
            }
            if (isPageHeader(l)) {
                continue;
            }
            parts.add(l);
        }
        String out = String.join(parts, ' ').normalizeSpace();
        return String.isBlank(out) ? null : out.left(32000);
    }

    // ---------------------------------------------------------------- lines

    @TestVisible
    private static List<String> cleanLines(String text) {
        List<String> out = new List<String>();
        for (String raw : text.replace('\r', '\n').split('\n')) {
            String l = raw == null ? '' : raw.normalizeSpace();
            if (isNoise(l)) {
                continue;
            }
            out.add(l);
        }
        return out;
    }

    private static Boolean isNoise(String l) {
        if (String.isBlank(l)) {
            return true;
        }
        // Watermark letters ("C", "u", "rr") and lone bullet glyphs.
        if (l.length() <= 2) {
            return true;
        }
        String lower = l.toLowerCase();
        return lower.startsWith('copyright') || lower.startsWith('electronic revision prior')
            || lower.contains('all hard copies are considered uncontrolled');
    }

    /** "Label: value" on one line, or "Label:" with the value on the next line. */
    @TestVisible
    private static String labelValue(List<String> lines, String label) {
        String prefix = label.toLowerCase() + ':';
        for (Integer i = 0; i < lines.size(); i++) {
            String l = lines[i];
            if (!l.toLowerCase().startsWith(prefix)) {
                continue;
            }
            String v = l.substring(prefix.length()).trim();
            if (String.isNotBlank(v)) {
                return v;
            }
            if (i + 1 < lines.size()) {
                String next = lines[i + 1];
                if (!looksLikeLabel(next) && !isStop(next)) {
                    return next.trim();
                }
            }
            return null;
        }
        return null;
    }

    private static Boolean looksLikeLabel(String l) {
        Integer c = l.indexOf(':');
        return c > 0 && c < 30 && l.substring(0, c).split(' ').size() <= 3;
    }

    private static Boolean isStop(String l) {
        return SECTION_STOPS.contains(l.toLowerCase());
    }

    private static String firstToken(String v) {
        if (String.isBlank(v)) {
            return null;
        }
        return v.trim().split(' ')[0];
    }

    // ---------------------------------------------------------------- dates

    /** 13-Nov-2024, 13 Nov 2024, 2024-11-13, 11/13/2024 -> 2024-11-13. Null when not a date. */
    @TestVisible
    private static String toIsoDate(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String v = raw.trim();
        Matcher m = Pattern.compile('^(\\d{1,2})[- ]([A-Za-z]{3})[A-Za-z]*[- ,]+(\\d{4})').matcher(v);
        if (m.find()) {
            Integer mon = MONTHS.get(m.group(2).toLowerCase());
            if (mon != null) {
                return iso(Integer.valueOf(m.group(3)), mon, Integer.valueOf(m.group(1)));
            }
        }
        m = Pattern.compile('^(\\d{4})-(\\d{1,2})-(\\d{1,2})').matcher(v);
        if (m.find()) {
            return iso(Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)), Integer.valueOf(m.group(3)));
        }
        m = Pattern.compile('^(\\d{1,2})/(\\d{1,2})/(\\d{4})').matcher(v);
        if (m.find()) {
            return iso(Integer.valueOf(m.group(3)), Integer.valueOf(m.group(1)), Integer.valueOf(m.group(2)));
        }
        return null;
    }

    private static String iso(Integer y, Integer mo, Integer d) {
        if (mo < 1 || mo > 12 || d < 1 || d > 31) {
            return null;
        }
        return String.valueOf(y) + '-' + String.valueOf(mo).leftPad(2, '0') + '-' + String.valueOf(d).leftPad(2, '0');
    }

    // ---------------------------------------------------------------- body sections

    private static Boolean isTocLine(String l) {
        return l.contains('....') || l.contains('. . .');
    }

    private static Boolean isPageHeader(String l) {
        String lower = l.toLowerCase();
        return lower.startsWith('document number:') || lower.startsWith('revision:')
            || lower.startsWith('title:') || lower.startsWith('department:')
            || lower.startsWith('effective date:');
    }

    private static Integer findHeading(List<String> lines, String regex, Integer fromIndex) {
        Pattern pat = Pattern.compile(regex);
        for (Integer i = fromIndex; i < lines.size(); i++) {
            String l = lines[i];
            if (isTocLine(l)) {
                continue;
            }
            if (pat.matcher(l).matches()) {
                return i;
            }
        }
        return -1;
    }

    private static void readPurpose(List<String> lines, Parsed p) {
        Integer start = findHeading(lines, '(?i)^\\d+\\.?\\s*purpose\\s*$', 0);
        if (start < 0) {
            return;
        }
        List<String> parts = new List<String>();
        for (Integer i = start + 1; i < lines.size(); i++) {
            String l = lines[i];
            if (Pattern.matches('(?i)^\\d+\\.?\\s*scope\\s*$', l) || Pattern.matches('(?i)^key updates\\s*$', l)
                || Pattern.matches('(?i)^\\d+\\.\\s+[A-Z][A-Za-z ]{2,40}$', l) && !l.toLowerCase().contains('purpose')) {
                break;
            }
            if (isPageHeader(l)) {
                continue;
            }
            parts.add(l);
            if (parts.size() > 40) {
                break;
            }
        }
        p.purpose = String.join(parts, ' ').normalizeSpace();
        p.purposeSummary = firstSentence(p.purpose, 600);
    }

    @TestVisible
    private static String firstSentence(String s, Integer maxLen) {
        if (String.isBlank(s)) {
            return null;
        }
        Integer cut = s.indexOf('. ');
        String out = cut > 0 ? s.substring(0, cut + 1) : s;
        if (out.length() > maxLen) {
            out = out.substring(0, maxLen - 1).trim() + '…';
        }
        return out.trim();
    }

    private static void readKeyUpdates(List<String> lines, Parsed p) {
        Integer start = findHeading(lines, '(?i)^key updates\\s*$', 0);
        if (start < 0) {
            return;
        }
        Set<String> seen = new Set<String>();
        for (Integer i = start + 1; i < lines.size(); i++) {
            String l = lines[i];
            if (Pattern.matches('(?i)^\\d+\\.?\\s*responsibilities\\s*$', l)) {
                break;
            }
            if (isPageHeader(l)) {
                continue;
            }
            String lower = l.toLowerCase();
            for (String marker : ALL_MARKERS) {
                if (lower.startsWith(marker) || lower.contains(' ' + marker + ':') || lower.startsWith('o ' + marker)) {
                    String label = marker.capitalize();
                    if (!p.changeMarkers.contains(label)) {
                        p.changeMarkers.add(label);
                    }
                    if (MAJOR_MARKERS.contains(marker)) {
                        p.hasMajorMarkers = true;
                    }
                }
            }
            String heading = asHeading(l);
            if (heading != null && !seen.contains(heading.toLowerCase())) {
                seen.add(heading.toLowerCase());
                p.keyUpdateHeadings.add(heading);
            }
        }
    }

    /** A short Title Case line with no sentence punctuation, e.g. "1. Additive Compatibility and Selection". */
    @TestVisible
    private static String asHeading(String l) {
        String s = l.replaceFirst('^\\d+\\.\\s*', '').trim();
        if (s.length() < 5 || s.length() > 70 || s.contains(':') || s.contains(',') || s.endsWith('.')) {
            return null;
        }
        List<String> words = s.split(' ');
        if (words.size() < 2 || words.size() > 9) {
            return null;
        }
        Integer longWords = 0;
        Integer capitalised = 0;
        for (String w : words) {
            if (w.length() <= 3) {
                continue;
            }
            longWords++;
            String first = w.substring(0, 1);
            if (first.isAllUpperCase()) {
                capitalised++;
            }
        }
        if (longWords == 0 || capitalised * 10 < longWords * 7) {
            return null;
        }
        return s;
    }

    // ---------------------------------------------------------------- last-page tables

    private static Integer exactLine(List<String> lines, String text) {
        for (Integer i = lines.size() - 1; i >= 0; i--) {
            if (lines[i].equalsIgnoreCase(text)) {
                return i;
            }
        }
        return -1;
    }

    private static void readRelatedDocuments(List<String> lines, Parsed p) {
        Integer start = exactLine(lines, 'Related Documents');
        if (start < 0) {
            return;
        }
        Pattern docNo = Pattern.compile('^([A-Z][A-Z0-9]*-[A-Z0-9][A-Z0-9-]*(\\[[A-Za-z0-9]+\\])?)(\\s.*)?$');
        for (Integer i = start + 1; i < lines.size(); i++) {
            String l = lines[i];
            if (isStop(l) || isPageHeader(l)) {
                break;
            }
            Matcher m = docNo.matcher(l);
            if (m.matches()) {
                String n = m.group(1);
                if (!p.relatedDocumentNumbers.contains(n)) {
                    p.relatedDocumentNumbers.add(n);
                }
            }
        }
    }

    private static void readRequirements(List<String> lines, Parsed p) {
        Integer start = exactLine(lines, 'Requirements');
        if (start < 0) {
            return;
        }
        for (Integer i = start + 1; i < lines.size(); i++) {
            String l = lines[i];
            String lower = l.toLowerCase();
            if (isStop(l) || isPageHeader(l)) {
                break;
            }
            if (TABLE_HEADERS.contains(lower) || lower.startsWith('all ') || l.contains(':')
                || l.length() > 80 || toIsoDate(l) != null) {
                continue;
            }
            if (!p.jobFunctions.contains(l)) {
                p.jobFunctions.add(l);
            }
        }
    }

    private static void readRevisions(List<String> lines, Parsed p) {
        Integer start = exactLine(lines, 'Revision History');
        if (start < 0) {
            return;
        }
        Pattern rev = Pattern.compile('^([0-9]{1,4}|[A-Z]{1,2})(\\s.*)?$');
        for (Integer i = start + 1; i < lines.size(); i++) {
            String l = lines[i];
            if (isStop(l) || isPageHeader(l)) {
                break;
            }
            if (TABLE_HEADERS.contains(l.toLowerCase())) {
                continue;
            }
            Matcher m = rev.matcher(l);
            if (m.matches() && toIsoDate(l) == null) {
                p.revisions.add(m.group(1));
            }
        }
    }
}
