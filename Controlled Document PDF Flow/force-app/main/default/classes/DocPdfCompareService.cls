/**
 * DocPdfCompareService
 * ----------------------
 * Compares the text of two versions of a document:
 *   1. cleans both (page headers, footers, page numbers, watermark letters, contents lines),
 *   2. splits each into sections by heading ("1. Purpose", "Key Updates", ...),
 *   3. matches sections by heading and compares them sentence by sentence,
 *   4. compares the labeled header values (Revision, Effective Date, Title, ...),
 *   5. writes a summary, a suggested Change Scope and suggested Changes text by rules,
 *      or the summary with a Prompt Builder template when one is set up.
 * No DML, so it can run between the Google Vision callouts and the save.
 */
public with sharing class DocPdfCompareService {

    public static final String FRONT_KEY = '__front';
    private static final Integer MAX_SENTENCES = 300;
    private static final Integer MAX_ITEMS = 12;

    public class Section {
        public String key;
        public String name;
        public List<String> lines = new List<String>();
    }

    public class SectionChange {
        public String name;
        public String status;        // Changed | Added | Removed | Unchanged
        public List<String> removed = new List<String>();
        public List<String> added = new List<String>();
    }

    public class HeaderChange {
        public String field;
        public String oldValue;
        public String newValue;
        public Boolean changed;
    }

    public class Comparison {
        public List<SectionChange> sections = new List<SectionChange>();
        public List<HeaderChange> header = new List<HeaderChange>();
        public Integer changedCount = 0;
        public Integer addedCount = 0;
        public Integer removedCount = 0;
        public Integer unchangedCount = 0;
        public String summary;
        public String summarySource;     // Rules | AI
        public String changeScope;       // Major Change | Minor Change | No Change
        public String changeScopeReason;
        public String changesText;
    }

    private static final List<String> HEADER_LABELS = new List<String>{
        'Document Number', 'Revision', 'Title', 'Effective Date', 'Document Category', 'Department'
    };

    private static final Set<String> COMMON_HEADINGS = new Set<String>{
        'purpose', 'scope', 'key updates', 'responsibilities', 'definitions', 'procedure', 'procedures',
        'references', 'related documents', 'requirements', 'revision history', 'approval history',
        'background', 'introduction', 'safety', 'records', 'attachments', 'appendix'
    };

    // ------------------------------------------------------------------ entry

    public static Comparison compare(String oldText, String newText, DocPdfMatchService.Result match,
                                     DocPdfMatchService.Settings st) {
        Comparison c = new Comparison();

        // ---- header values
        for (String lbl : HEADER_LABELS) {
            String o = DocPdfFieldParser.labeledValue(oldText, lbl);
            String n = DocPdfFieldParser.labeledValue(newText, lbl);
            if (String.isBlank(o) && String.isBlank(n)) {
                continue;
            }
            HeaderChange h = new HeaderChange();
            h.field = lbl;
            h.oldValue = o == null ? '' : o.left(120);
            h.newValue = n == null ? '' : n.left(120);
            h.changed = norm(o) != norm(n);
            c.header.add(h);
        }

        // ---- sections
        List<Section> oldSections = sections(oldText);
        List<Section> newSections = sections(newText);
        Map<String, Section> oldByKey = new Map<String, Section>();
        for (Section s : oldSections) {
            if (!oldByKey.containsKey(s.key)) {
                oldByKey.put(s.key, s);
            }
        }
        Set<String> seen = new Set<String>();
        for (Section ns : newSections) {
            if (seen.contains(ns.key)) {
                continue;
            }
            seen.add(ns.key);
            SectionChange sc = new SectionChange();
            sc.name = ns.name;
            Section os = oldByKey.get(ns.key);
            if (os == null) {
                sc.status = 'Added';
                for (String x : sentences(ns.lines)) {
                    addCapped(sc.added, x);
                }
            } else {
                diffSentences(sentences(os.lines), sentences(ns.lines), sc);
                sc.status = sc.removed.isEmpty() && sc.added.isEmpty() ? 'Unchanged' : 'Changed';
            }
            if (ns.key == FRONT_KEY && sc.status == 'Unchanged') {
                continue; // a title page that did not change is not worth a row
            }
            c.sections.add(sc);
        }
        for (Section os : oldSections) {
            if (seen.contains(os.key)) {
                continue;
            }
            seen.add(os.key);
            SectionChange sc = new SectionChange();
            sc.name = os.name;
            sc.status = 'Removed';
            for (String x : sentences(os.lines)) {
                addCapped(sc.removed, x);
            }
            c.sections.add(sc);
        }
        for (SectionChange sc : c.sections) {
            if (sc.status == 'Changed') { c.changedCount++; }
            else if (sc.status == 'Added') { c.addedCount++; }
            else if (sc.status == 'Removed') { c.removedCount++; }
            else { c.unchangedCount++; }
        }

        rulesSummary(c, match);
        if (st != null && String.isNotBlank(st.promptTemplate)
            && (c.changedCount + c.addedCount + c.removedCount) > 0) {
            String ai = aiSummary(st.promptTemplate, differencesText(c, match));
            if (String.isNotBlank(ai)) {
                c.summary = ai.trim().left(4000);
                c.summarySource = 'AI';
            }
        }
        return c;
    }

    // ------------------------------------------------------------------ sections

    /** The text split into sections by heading; text before the first heading is the front section. */
    public static List<Section> sections(String text) {
        List<Section> out = new List<Section>();
        Section current = new Section();
        current.key = FRONT_KEY;
        current.name = 'Opening text';
        out.add(current);
        for (String l : DocPdfFieldParser.cleanLinesOf(text)) {
            if (DocPdfFieldParser.isRepeatedHeader(l) || DocPdfFieldParser.isContentsLine(l)
                || Pattern.matches('(?i)^page \\d+( of \\d+)?$', l)) {
                continue;
            }
            String heading = headingOf(l);
            if (heading != null) {
                current = new Section();
                current.name = l.trim().left(100);
                current.key = heading;
                out.add(current);
                continue;
            }
            current.lines.add(l);
        }
        if (out[0].lines.isEmpty() && out.size() > 1) {
            out.remove(0);
        }
        return out;
    }

    /** The matching key of a heading line ("1. Purpose" -> "purpose"), or null when the line is not a heading. */
    @TestVisible
    private static String headingOf(String l) {
        String t = l.trim();
        if (t.length() < 4 || t.length() > 70 || t.endsWith('.') || t.contains(',')) {
            return null;
        }
        String bare = t.replaceFirst('^\\d+(\\.\\d+)*\\.?\\s*', '').removeEnd(':').trim();
        String key = bare.toLowerCase();
        if (COMMON_HEADINGS.contains(key)) {
            return key;
        }
        // Numbered heading: "2. Additive Measurement and Dosage Controls".
        if (Pattern.matches('^\\d+(\\.\\d+)*\\.?\\s+[A-Z][A-Za-z/&\\- ]{2,65}$', t) && !bare.contains(':')) {
            return key;
        }
        return null;
    }

    /**
     * Sentences of a section, joined across line breaks. A short line with no closing punctuation that
     * starts a new line of thought (a title or heading, e.g. "SUMMARY") stays a line of its own, so it is
     * not glued to the sentence after it.
     */
    @TestVisible
    private static List<String> sentences(List<String> lines) {
        List<String> out = new List<String>();
        List<String> buf = new List<String>();
        for (Integer k = 0; k < lines.size(); k++) {
            String l = lines[k] == null ? '' : lines[k].normalizeSpace();
            if (l.length() == 0) {
                continue;
            }
            Boolean atBoundary = buf.isEmpty() || Pattern.matches('.*[.;:!?]$', buf[buf.size() - 1]);
            Boolean nextStartsNew = k == lines.size() - 1 || lines[k + 1] == null
                || Pattern.matches('^[A-Z0-9\\[(].*', lines[k + 1].trim());
            if (atBoundary && nextStartsNew && l.length() <= 60 && !Pattern.matches('.*[.;:!?,]$', l)) {
                splitInto(String.join(buf, ' '), out);
                buf.clear();
                if (l.length() > 2) {
                    out.add(l);
                }
                continue;
            }
            buf.add(l);
        }
        splitInto(String.join(buf, ' '), out);
        while (out.size() > MAX_SENTENCES) {
            out.remove(out.size() - 1);
        }
        return out;
    }

    private static void splitInto(String joined, List<String> out) {
        joined = joined == null ? '' : joined.normalizeSpace();
        if (String.isBlank(joined)) {
            return;
        }
        for (String s : joined.split('(?<=[.;!?])\\s+')) {
            if (String.isNotBlank(s) && s.trim().length() > 2) {
                out.add(s.trim());
            }
        }
    }

    /** Sentence-level difference (longest common subsequence on normalized sentences). */
    @TestVisible
    private static void diffSentences(List<String> a, List<String> b, SectionChange sc) {
        Integer n = a.size();
        Integer m = b.size();
        List<String> na = new List<String>();
        for (String x : a) { na.add(norm(x)); }
        List<String> nb = new List<String>();
        for (String x : b) { nb.add(norm(x)); }

        Integer w = m + 1;
        List<Integer> dp = new List<Integer>();
        for (Integer i = 0; i < (n + 1) * w; i++) {
            dp.add(0);
        }
        for (Integer i = n - 1; i >= 0; i--) {
            for (Integer j = m - 1; j >= 0; j--) {
                if (na[i] == nb[j]) {
                    dp[i * w + j] = dp[(i + 1) * w + j + 1] + 1;
                } else {
                    Integer down = dp[(i + 1) * w + j];
                    Integer right = dp[i * w + j + 1];
                    dp[i * w + j] = down >= right ? down : right;
                }
            }
        }
        Integer i = 0;
        Integer j = 0;
        while (i < n && j < m) {
            if (na[i] == nb[j]) {
                i++;
                j++;
            } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
                addCapped(sc.removed, a[i]);
                i++;
            } else {
                addCapped(sc.added, b[j]);
                j++;
            }
        }
        while (i < n) { addCapped(sc.removed, a[i]); i++; }
        while (j < m) { addCapped(sc.added, b[j]); j++; }
    }

    private static void addCapped(List<String> items, String s) {
        if (items.size() < MAX_ITEMS) {
            items.add(s.left(400));
        } else if (items.size() == MAX_ITEMS) {
            items.add('…and more.');
        }
    }

    /** Lower case letters and digits only, so OCR spacing and punctuation do not count as changes. */
    @TestVisible
    private static String norm(String s) {
        return s == null ? '' : s.toLowerCase().replaceAll('[^a-z0-9]', '');
    }

    // ------------------------------------------------------------------ summary

    private static final String STRONG_WORDS = '(?i).*\\b(must|shall|required|requirement|mandatory|prohibited)\\b.*';

    @TestVisible
    private static void rulesSummary(Comparison c, DocPdfMatchService.Result match) {
        List<String> changed = new List<String>();
        List<String> added = new List<String>();
        List<String> removed = new List<String>();
        Boolean strong = false;
        for (SectionChange sc : c.sections) {
            String nm = sc.name.replaceFirst('^\\d+(\\.\\d+)*\\.?\\s*', '');
            if (sc.status == 'Changed') { changed.add(nm); }
            else if (sc.status == 'Added') { added.add(nm); }
            else if (sc.status == 'Removed') { removed.add(nm); }
            for (String x : sc.added) {
                if (Pattern.matches(STRONG_WORDS, x)) {
                    strong = true;
                }
            }
        }
        List<String> parts = new List<String>();
        for (HeaderChange h : c.header) {
            if (h.changed && h.field == 'Revision' && String.isNotBlank(h.oldValue) && String.isNotBlank(h.newValue)) {
                parts.add('Revision ' + h.oldValue + ' → ' + h.newValue + '.');
            }
        }
        if (changed.isEmpty() && added.isEmpty() && removed.isEmpty()) {
            parts.add('No differences were found in the text of the two documents.');
            c.changeScope = 'No Change';
            c.changeScopeReason = 'The text is the same.';
            c.changesText = '';
        } else {
            if (!changed.isEmpty()) { parts.add(listSentence('Changed', changed)); }
            if (!added.isEmpty()) { parts.add(listSentence('Added', added)); }
            if (!removed.isEmpty()) { parts.add(listSentence('Removed', removed)); }
            if (c.unchangedCount > 0) {
                parts.add(c.unchangedCount + (c.unchangedCount == 1 ? ' section is' : ' sections are') + ' unchanged.');
            }
            if (!added.isEmpty() || !removed.isEmpty() || strong) {
                c.changeScope = 'Major Change';
                c.changeScopeReason = !added.isEmpty() || !removed.isEmpty()
                    ? 'Sections were added or removed.'
                    : 'New text includes requirements (must, shall, required).';
            } else {
                c.changeScope = 'Minor Change';
                c.changeScopeReason = 'Existing sections were edited; no sections or requirements were added.';
            }
            List<String> ct = new List<String>();
            if (!changed.isEmpty()) { ct.add('Updated ' + String.join(changed, ', ')); }
            if (!added.isEmpty()) { ct.add('added ' + String.join(added, ', ')); }
            if (!removed.isEmpty()) { ct.add('removed ' + String.join(removed, ', ')); }
            c.changesText = (String.join(ct, '; ') + '.').capitalize().left(1000);
        }
        if (match != null && match.revisionDirection == 'lower') {
            parts.add('Note: the uploaded PDF has an older revision than the current document.');
        }
        c.summary = String.join(parts, ' ').left(4000);
        c.summarySource = 'Rules';
    }

    private static String listSentence(String verb, List<String> names) {
        List<String> shown = new List<String>();
        for (Integer i = 0; i < names.size() && i < 5; i++) {
            shown.add(names[i]);
        }
        String more = names.size() > 5 ? ' and ' + (names.size() - 5) + ' more' : '';
        return verb + ': ' + String.join(shown, ', ') + more + '.';
    }

    /** The differences as compact text for the prompt template. */
    @TestVisible
    private static String differencesText(Comparison c, DocPdfMatchService.Result match) {
        List<String> out = new List<String>();
        if (match != null) {
            out.add('Verdict: ' + match.verdict + '. Text shared: ' + match.shared + '%.');
        }
        for (HeaderChange h : c.header) {
            if (h.changed) {
                out.add('Header ' + h.field + ': "' + h.oldValue + '" -> "' + h.newValue + '"');
            }
        }
        for (SectionChange sc : c.sections) {
            if (sc.status == 'Unchanged') {
                continue;
            }
            out.add('Section "' + sc.name + '" (' + sc.status + ')');
            for (String x : sc.removed) { out.add('  - removed: ' + x); }
            for (String x : sc.added) { out.add('  + added: ' + x); }
        }
        return String.join(out, '\n').left(12000);
    }

    /** Summary from a Prompt Builder flex template with a text input named Differences; null on any failure. */
    private static String aiSummary(String templateName, String differences) {
        try {
            ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            input.isPreview = false;
            ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
            wrapped.value = differences;
            input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Differences' => wrapped };
            input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            input.additionalConfig.applicationName = 'PromptBuilderPreview';
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation out =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, input);
            if (out != null && out.generations != null && !out.generations.isEmpty()) {
                return out.generations[0].text;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Prompt template summary failed: ' + e.getMessage());
        }
        return null;
    }
}
