/**
 * DocPdfNumbering
 * -----------------
 * Template and numbering rules by Document Category, read from Doc PDF Agent Setting (Default),
 * Category Templates: one line per category, parts separated by |
 *
 *   Category | Template Document Number | Number Prefix | section headings separated by ;
 *   Policy   | TMP-POL-000              | POL           | Policy Purpose; Principles of this Policy; Definitions
 *
 * - The template (a released Template Document) numbers the new document in ComplianceQuest.
 * - With no released template, or when ComplianceQuest leaves the number blank, the number is
 *   the prefix plus the next free number (POL-000004): the highest existing number with that
 *   prefix, plus one. A category with no line uses its initials (Work Instruction = WI).
 * - The headings pick the best-fit category (and so template) when AI is off.
 */
public with sharing class DocPdfNumbering {

    /** Digits in a suggested number (POL-000001), as ComplianceQuest numbers them. */
    public static Integer digits = 6;

    public class CategoryTemplate {
        public String category;
        public String templateNumber;
        public String prefix;
        public List<String> headings = new List<String>();
    }

    public class Template {
        public Id id;
        public String name;
        public String documentNumber;
    }

    public class BestFit {
        public String category;
        public Integer found = 0;
        public Integer total = 0;
        public List<String> foundHeadings = new List<String>();
        public String describe() {
            return category + ' (' + found + ' of ' + total + ' template sections found: '
                + String.join(foundHeadings, ', ') + ')';
        }
    }

    /** Tests set this instead of the custom metadata setting. */
    @TestVisible
    private static String testLines;

    // ------------------------------------------------------------------ setup

    public static List<CategoryTemplate> load() {
        String raw = testLines;
        if (raw == null) {
            // SOQL, not getInstance(): getInstance() returns only the first 255 characters of a long text field.
            List<Doc_PDF_Agent_Setting__mdt> st = [
                SELECT Category_Templates__c FROM Doc_PDF_Agent_Setting__mdt WHERE DeveloperName = 'Default' LIMIT 1
            ];
            raw = st.isEmpty() ? null : st[0].Category_Templates__c;
        }
        return parse(raw);
    }

    @TestVisible
    private static List<CategoryTemplate> parse(String raw) {
        List<CategoryTemplate> out = new List<CategoryTemplate>();
        if (String.isBlank(raw)) {
            return out;
        }
        for (String line : raw.split('\n')) {
            if (String.isBlank(line) || line.trim().startsWith('#')) {
                continue;
            }
            List<String> parts = line.split('\\|');
            CategoryTemplate ct = new CategoryTemplate();
            ct.category = part(parts, 0);
            if (String.isBlank(ct.category)) {
                continue;
            }
            ct.templateNumber = part(parts, 1);
            ct.prefix = part(parts, 2);
            String hs = part(parts, 3);
            if (hs != null) {
                for (String h : hs.split(';')) {
                    if (String.isNotBlank(h)) {
                        ct.headings.add(h.trim());
                    }
                }
            }
            out.add(ct);
        }
        return out;
    }

    private static String part(List<String> parts, Integer i) {
        if (i >= parts.size()) {
            return null;
        }
        String v = parts[i].trim();
        return String.isBlank(v) ? null : v;
    }

    public static CategoryTemplate forCategory(String category) {
        if (String.isBlank(category)) {
            return null;
        }
        for (CategoryTemplate ct : load()) {
            if (ct.category.equalsIgnoreCase(category.trim())) {
                return ct;
            }
        }
        return null;
    }

    /** The number prefix for a category: from its line, else its initials (Work Instruction = WI). */
    public static String prefixFor(String category) {
        CategoryTemplate ct = forCategory(category);
        if (ct != null && String.isNotBlank(ct.prefix)) {
            return ct.prefix.toUpperCase();
        }
        if (String.isBlank(category)) {
            return 'DOC';
        }
        List<String> words = category.trim().split('[^A-Za-z0-9]+');
        String p = '';
        if (words.size() == 1) {
            p = words[0].left(3);
        } else {
            for (String w : words) {
                p += w.left(1);
            }
        }
        p = p.toUpperCase();
        return String.isBlank(p) ? 'DOC' : p;
    }

    // ------------------------------------------------------------------ templates

    /** The released (Current) Template Document with this Document Number, or null. */
    public static Template releasedTemplate(String templateNumber) {
        if (String.isBlank(templateNumber)) {
            return null;
        }
        String n = templateNumber.trim();
        Schema.RecordTypeInfo rt = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Template_Document');
        if (rt == null) {
            return null;
        }
        Id templateType = rt.getRecordTypeId();
        List<compliancequest__SQX_Controlled_Document__c> ds = [
            SELECT Id, Name, compliancequest__Document_Number__c
            FROM compliancequest__SQX_Controlled_Document__c
            WHERE compliancequest__Document_Number__c = :n
            AND RecordTypeId = :templateType
            AND compliancequest__Document_Status__c = 'Current'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (ds.isEmpty()) {
            return null;
        }
        Template t = new Template();
        t.id = ds[0].Id;
        t.name = ds[0].Name;
        t.documentNumber = ds[0].compliancequest__Document_Number__c;
        return t;
    }

    /** The released template for a category, or null. */
    public static Template templateForCategory(String category) {
        CategoryTemplate ct = forCategory(category);
        return ct == null ? null : releasedTemplate(ct.templateNumber);
    }

    // ------------------------------------------------------------------ numbers

    /** The prefix plus the next free number: POL-000004 when POL-000003 is the highest. */
    public static String nextNumber(String prefix) {
        String p = String.isBlank(prefix) ? 'DOC' : prefix.trim().toUpperCase();
        Integer highest = new AllDocuments().highest(p);
        return format(p, highest + 1);
    }

    @TestVisible
    private static String format(String prefix, Integer n) {
        String num = String.valueOf(n);
        return prefix + '-' + num.leftPad(Math.max(digits, num.length()), '0');
    }

    /** True when any Controlled Document (visible or not) already has this number. */
    public static Boolean isTaken(String documentNumber) {
        return String.isNotBlank(documentNumber) && new AllDocuments().exists(documentNumber.trim());
    }

    /** A free number: the one given if it is free, else the next free one with its prefix. */
    public static String freeNumber(String wanted, String prefix) {
        if (String.isNotBlank(wanted) && !isTaken(wanted)) {
            return wanted.trim();
        }
        String p = prefix;
        if (String.isNotBlank(wanted) && wanted.contains('-')) {
            p = wanted.substringBeforeLast('-');
        }
        return nextNumber(p);
    }

    /** Numbers are checked across all documents, including ones the user cannot see, so none is reused. */
    private without sharing class AllDocuments {
        Integer highest(String prefix) {
            String likeValue = prefix + '-%';
            Pattern pat = Pattern.compile('^' + Pattern.quote(prefix + '-') + '(\\d{1,9})$');
            Integer best = 0;
            for (compliancequest__SQX_Controlled_Document__c d : [
                SELECT compliancequest__Document_Number__c
                FROM compliancequest__SQX_Controlled_Document__c
                WHERE compliancequest__Document_Number__c LIKE :likeValue
                ORDER BY compliancequest__Document_Number__c DESC
                LIMIT 2000
            ]) {
                Matcher m = pat.matcher(d.compliancequest__Document_Number__c.trim().toUpperCase());
                if (m.matches()) {
                    best = Math.max(best, Integer.valueOf(m.group(1)));
                }
            }
            return best;
        }

        Boolean exists(String documentNumber) {
            return ![
                SELECT Id FROM compliancequest__SQX_Controlled_Document__c
                WHERE compliancequest__Document_Number__c = :documentNumber
                LIMIT 1
            ].isEmpty();
        }
    }

    // ------------------------------------------------------------------ best fit

    /**
     * The category whose template headings appear most in the text (as heading lines).
     * Null when no category has at least two of its headings (or its only heading) in the text.
     */
    public static BestFit bestFit(String text) {
        if (String.isBlank(text)) {
            return null;
        }
        Set<String> headingLines = new Set<String>();
        for (String l : text.split('\n')) {
            String h = normalizeHeading(l);
            if (h != null) {
                headingLines.add(h);
            }
        }
        BestFit best = null;
        for (CategoryTemplate ct : load()) {
            if (ct.headings.isEmpty()) {
                continue;
            }
            BestFit bf = new BestFit();
            bf.category = ct.category;
            bf.total = ct.headings.size();
            for (String h : ct.headings) {
                if (headingLines.contains(normalizeHeading(h))) {
                    bf.found++;
                    bf.foundHeadings.add(h);
                }
            }
            Boolean enough = bf.found >= 2 || (bf.found == 1 && bf.total == 1);
            if (!enough) {
                continue;
            }
            if (best == null || bf.found > best.found
                || (bf.found == best.found && bf.found * best.total > best.found * bf.total)) {
                best = bf;
            }
        }
        return best;
    }

    /** A short line as a heading key: numbering, punctuation and case removed; null for long lines. */
    @TestVisible
    private static String normalizeHeading(String line) {
        if (line == null) {
            return null;
        }
        String l = line.trim();
        if (l.length() == 0 || l.length() > 80) {
            return null;
        }
        l = l.replaceAll('^(section\\s+)?[0-9IVXivx]{1,4}(\\.[0-9]{1,3})*[.)]?\\s+', '');
        l = l.replaceAll('\\(.*?\\)', ' ');
        l = l.replaceAll('[^A-Za-z0-9 ]', ' ').normalizeSpace().toLowerCase();
        return l.length() == 0 ? null : l;
    }
}
