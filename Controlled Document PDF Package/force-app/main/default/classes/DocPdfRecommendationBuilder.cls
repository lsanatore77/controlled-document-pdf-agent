/**
 * DocPdfRecommendationBuilder
 * -----------------------------
 * Turns the text of a PDF into one Doc_PDF_Field__c row per Controlled Document field
 * listed in the Doc PDF Field Config custom metadata (active records, by Sort Order).
 * Each record says how its value is found (Value Source):
 *
 *   Labeled_Value          text after "PDF Label:" in the PDF
 *   Section_First_Sentence first sentence of the section headed PDF Label
 *   Section_Text           the whole section headed PDF Label
 *   Picklist_Match         the labeled value matched to the picklist, then Match Rules,
 *                          then Default Value
 *   Lookup_Match           the labeled value matched to a record Name (or Document Number),
 *                          then Match Rules, then Default Value
 *   Fixed_Value            always Default Value (shown fixed)
 *   User_Input             left for the user (picklist and lookup choices offered)
 *
 * Each row lands in one section of the review:
 *   ready    : printed in the PDF and matched exactly
 *   review   : found, but generated or uncertain (section text, rules, closest match, default)
 *   input    : required and not found: the user must give a value
 *   optional : not found and not required: left blank unless the user picks a value
 *   system   : fixed (Fixed_Value or not Editable), plus the Primary Content row
 *
 * AI first: when a field has an AI Answer (title, description, documentType) and the Field
 * Prompt Template on Doc PDF Agent Setting answers, that value is used (source "Written by AI",
 * always left for review). When AI is off, fails or gives a value that does not fit the field,
 * the field falls back to the Value Source rules above, and the note says why.
 * Default Value {First Line} means: the first line of the PDF that reads like a title.
 *
 * Never invents a value: anything not found in the PDF, the rules or the defaults is left
 * blank. Re-running for the same proposal replaces its rows.
 */
public with sharing class DocPdfRecommendationBuilder {

    public static final String CD = 'compliancequest__SQX_Controlled_Document__c';
    public static final String PRIMARY_CONTENT_KEY = 'info:primaryContent';
    public static final String CATEGORY_FIELD = 'compliancequest__document_category__c';
    public static final String TEMPLATE_FIELD = 'compliancequest__document_type__c';
    public static final String NUMBER_FIELD = 'compliancequest__document_number__c';
    public static final String BEST_FIT_SOURCE = 'Best fit';
    public static final String FROM_CATEGORY_SOURCE = 'From Category';
    public static final String NUMBER_SOURCE = 'Numbering';

    public class Summary {
        public Boolean success = false;
        public String message;
        public Integer readyCount = 0;
        public Integer reviewCount = 0;
        public Integer inputCount = 0;
        public Integer optionalCount = 0;
        public Integer relatedCount = 0;
    }

    public class Option {
        public String value;
        public String label;
        public String detail;
        public Option(String value, String label, String detail) {
            this.value = value;
            this.label = label;
            this.detail = detail;
        }
    }

    /** One configured field: a Doc_PDF_Field_Config__mdt record. */
    public class FieldConfig {
        public String apiName;
        public String label;
        public Decimal sortOrder;
        public Boolean required = false;
        public Boolean editable = true;
        public String source;
        public String pdfLabel;
        public String defaultValue;
        public String matchRules;
        public String helpText;
        public String aiAnswer;
    }

    public static final String AI_SOURCE = 'Written by AI';
    public static final String FIRST_LINE_TOKEN = '{first line}';

    /** Tests set this to use their own field list instead of the custom metadata. */
    @TestVisible
    private static List<FieldConfig> testConfig;

    private Id proposalId;
    private String text;
    private String fileName;
    private Integer sortOrder = 0;
    private List<Doc_PDF_Field__c> rows = new List<Doc_PDF_Field__c>();
    private List<String> skipped = new List<String>();
    /** The Document Category found (picklist value), used for the template and the number. */
    private String categoryValue;
    /** The template set on the Template row, if any. */
    private Option templateChosen;
    private Boolean numberConfigured = false;
    @TestVisible
    private DocPdfAiSuggestions.Result ai;
    private Map<String, Schema.SObjectField> cdFields =
        compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().fields.getMap();

    public DocPdfRecommendationBuilder(Id proposalId, String text, String fileName) {
        this.proposalId = proposalId;
        this.text = text;
        this.fileName = fileName;
    }

    // ------------------------------------------------------------------ entry

    public static Summary build(Id proposalId, String text, Integer pagesRead, Integer totalPages,
                                Boolean extractionSucceeded, String extractionMessage) {
        Summary s = new Summary();
        Doc_PDF_Proposal__c proposal = new Doc_PDF_Proposal__c(Id = proposalId);
        proposal.Pages_Read__c = pagesRead;
        proposal.Total_Pages__c = totalPages;

        if (extractionSucceeded != true || String.isBlank(text)) {
            proposal.Status__c = 'Failed';
            proposal.Message__c = String.isBlank(extractionMessage) ? 'No text could be read from the file.' : extractionMessage;
            update as user proposal;
            s.message = proposal.Message__c;
            return s;
        }

        List<FieldConfig> config = loadConfig();
        if (config.isEmpty()) {
            proposal.Status__c = 'Failed';
            proposal.Message__c = 'No fields are set up for this agent. Add active Doc PDF Field Config records in Setup, Custom Metadata Types.';
            update as user proposal;
            s.message = proposal.Message__c;
            return s;
        }

        String fileName = proposalFileName(proposalId);
        DocPdfRecommendationBuilder b = new DocPdfRecommendationBuilder(proposalId, text, fileName);
        // AI first, before any record is written (the template call cannot follow uncommitted work).
        Boolean anyAi = false;
        for (FieldConfig c : config) {
            anyAi = anyAi || String.isNotBlank(c.aiAnswer);
        }
        if (anyAi) {
            b.ai = DocPdfAiSuggestions.suggest(text);
            proposal.AI_Status__c = b.ai.status;
        } else {
            proposal.AI_Status__c = 'AI suggestions: not used. No field has an AI Answer in Doc PDF Field Config.';
        }
        b.addAll(config);

        delete [SELECT Id FROM Doc_PDF_Field__c WHERE Proposal__c = :proposalId];
        insert as user b.rows;

        for (Doc_PDF_Field__c r : b.rows) {
            if (r.Section__c == 'ready') { s.readyCount++; }
            else if (r.Section__c == 'review') { s.reviewCount++; }
            else if (r.Section__c == 'input') { s.inputCount++; }
            else if (r.Section__c == 'optional') { s.optionalCount++; }
        }

        String pagesNote = '';
        if (pagesRead != null && totalPages != null && pagesRead < totalPages) {
            pagesNote = ' I could read only ' + pagesRead + ' of ' + totalPages + ' pages, so some values may be missing.';
        }
        String skippedNote = b.skipped.isEmpty() ? '' : ' Skipped from the setup: ' + String.join(b.skipped, '; ') + '.';
        s.success = true;
        String readNote = pagesRead == 1 && totalPages == 1
            ? 'I read ' + nvl(fileName, 'the file') + '. '
            : 'I read ' + pagesRead + (pagesRead == 1 ? ' page' : ' pages') + ' of ' + nvl(fileName, 'the file') + '. ';
        s.message = (readNote
            + countText(s.readyCount, 'is ready', 'are ready') + ', '
            + countText(s.reviewCount, 'needs your review', 'need your review') + ' and '
            + countText(s.inputCount, 'needs your input', 'need your input') + '.'
            + pagesNote + skippedNote + ' Showing the review now.').left(1000);

        proposal.Status__c = 'Ready for Review';
        proposal.Extracted_Text__c = text.left(131072);
        proposal.Message__c = s.message;
        update as user proposal;
        return s;
    }

    private static String countText(Integer n, String one, String many) {
        return n + (n == 1 ? ' field ' + one : ' fields ' + many);
    }

    private static String proposalFileName(Id proposalId) {
        List<Doc_PDF_Proposal__c> ps = [SELECT File_Name__c FROM Doc_PDF_Proposal__c WHERE Id = :proposalId LIMIT 1];
        return ps.isEmpty() ? null : ps[0].File_Name__c;
    }

    // ------------------------------------------------------------------ configuration

    /** Active Doc PDF Field Config records, lowest Sort Order first. */
    public static List<FieldConfig> loadConfig() {
        if (testConfig != null) {
            return testConfig;
        }
        List<ConfigSort> sorted = new List<ConfigSort>();
        // SOQL, not getAll(): getAll() returns only the first 255 characters of long text fields (Match Rules).
        for (Doc_PDF_Field_Config__mdt m : [
            SELECT DeveloperName, Active__c, Field_API_Name__c, Field_Label__c, Sort_Order__c, Required__c, Editable__c,
                   Value_Source__c, PDF_Label__c, Default_Value__c, Match_Rules__c, Help_Text__c, AI_Answer__c
            FROM Doc_PDF_Field_Config__mdt
        ]) {
            if (m.Active__c != true || String.isBlank(m.Field_API_Name__c)) {
                continue;
            }
            FieldConfig c = new FieldConfig();
            c.apiName = m.Field_API_Name__c.trim();
            c.label = m.Field_Label__c;
            c.sortOrder = m.Sort_Order__c == null ? 9999 : m.Sort_Order__c;
            c.required = m.Required__c == true;
            c.editable = m.Editable__c != false;
            c.source = String.isBlank(m.Value_Source__c) ? 'Labeled_Value' : m.Value_Source__c;
            c.pdfLabel = m.PDF_Label__c;
            c.defaultValue = m.Default_Value__c;
            c.matchRules = m.Match_Rules__c;
            c.helpText = m.Help_Text__c;
            c.aiAnswer = String.isBlank(m.AI_Answer__c) ? null : m.AI_Answer__c.trim();
            sorted.add(new ConfigSort(c));
        }
        sorted.sort();
        List<FieldConfig> out = new List<FieldConfig>();
        for (ConfigSort cs : sorted) {
            out.add(cs.config);
        }
        return out;
    }

    private class ConfigSort implements Comparable {
        FieldConfig config;
        ConfigSort(FieldConfig c) {
            config = c;
        }
        public Integer compareTo(Object other) {
            FieldConfig o = ((ConfigSort) other).config;
            if (config.sortOrder == o.sortOrder) {
                return config.apiName.compareTo(o.apiName);
            }
            return config.sortOrder < o.sortOrder ? -1 : 1;
        }
    }

    // ------------------------------------------------------------------ rows

    @TestVisible
    private void addAll(List<FieldConfig> config) {
        Set<String> seen = new Set<String>();
        for (FieldConfig c : config) {
            String key = c.apiName.toLowerCase();
            if (seen.contains(key)) {
                skipped.add(c.apiName + ' (listed twice)');
                continue;
            }
            seen.add(key);
            if (key == NUMBER_FIELD) {
                numberConfigured = true;
            }
            try {
                addConfigured(c);
            } catch (Exception e) {
                skipped.add(c.apiName + ' (' + e.getMessage() + ')');
            }
        }
        if (!numberConfigured) {
            try {
                addNumberRow();
            } catch (Exception e) {
                skipped.add('Document Number (' + e.getMessage() + ')');
            }
        }
        addRow(PRIMARY_CONTENT_KEY, 'Primary Content', 'system', 'Fixed', 'info', null,
            nvl(fileName, 'The uploaded file'),
            'The uploaded file (PDF or Word) becomes the document\'s Primary Content, unchanged (check-in method: Manual).',
            false, null, 'locked');
    }

    private void addConfigured(FieldConfig c) {
        Schema.SObjectField sf = cdFields.get(c.apiName.toLowerCase());
        if (sf == null) {
            skipped.add(c.apiName + ' (no such field on Controlled Document)');
            return;
        }
        Schema.DescribeFieldResult d = sf.getDescribe();
        if (!d.isCreateable()) {
            skipped.add(c.apiName + ' (you cannot set this field)');
            return;
        }
        String apiName = d.getName();
        String label = String.isNotBlank(c.label) ? c.label
            : (apiName == 'RecordTypeId' ? 'Record Type' : d.getLabel());
        String fieldType = typeOf(d);
        Boolean isRecordType = apiName == 'RecordTypeId';
        List<Option> opts = isRecordType ? recordTypeOptions()
            : fieldType == 'picklist' ? picklistOptions(d)
            : fieldType == 'reference' ? lookupOptions(d)
            : null;

        Found f = isTemplateField(d) && categoryValue != null ? templateFromCategory(c, d, fieldType, opts) : null;
        if (f == null) {
            f = find(c, d, fieldType, opts);
        }
        if (apiName.toLowerCase() == CATEGORY_FIELD) {
            categoryValue = f.value;
        }
        if (isTemplateField(d) && f.value != null) {
            templateChosen = new Option(f.value, f.display, null);
        }
        Boolean fixed = c.source == 'Fixed_Value' || c.editable == false;

        String section;
        String source;
        String decision;
        if (fixed) {
            section = 'system';
            source = 'Fixed';
            decision = 'locked';
        } else if (f.value != null) {
            section = f.exact ? 'ready' : 'review';
            source = f.source;
            decision = f.exact ? 'accept' : 'undecided';
        } else if (c.required) {
            section = 'input';
            source = 'Your input';
            decision = 'undecided';
        } else {
            section = 'optional';
            source = 'Your input';
            decision = 'clear';
        }

        String evidence = String.isNotBlank(c.helpText) ? c.helpText : f.evidence;
        if (String.isNotBlank(c.helpText) && String.isNotBlank(f.evidence) && !fixed
            && (f.value == null || f.source == AI_SOURCE || String.isNotBlank(f.aiNote))) {
            evidence = c.helpText + ' ' + f.evidence;
        }
        if (fixed && f.value == null) {
            evidence = 'No fixed value could be set: ' + f.evidence;
        }
        addRow(apiName, label, section, source, isRecordType ? 'reference' : fieldType, f.value, f.display,
            evidence, c.required, fixed ? null : opts, decision);
    }

    /** What was found for one field. */
    private class Found {
        String value;
        String display;
        Boolean exact = false;
        String source = 'From PDF';
        String evidence;
        String aiNote;
    }

    /** AI first (when the field has an AI Answer), then the Value Source rules. */
    private Found find(FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts) {
        String aiNote = null;
        if (String.isNotBlank(c.aiAnswer) && c.source != 'Fixed_Value' && c.editable != false) {
            if (ai == null || ai.used != true) {
                aiNote = 'AI was off, so the rules were used.';
            } else {
                String suggested = ai.get(c.aiAnswer);
                if (String.isBlank(suggested)) {
                    aiNote = 'AI gave no ' + c.aiAnswer + '.';
                } else {
                    Found viaAi = fromAi(c, d, fieldType, opts, suggested);
                    if (viaAi.value != null) {
                        return viaAi;
                    }
                    aiNote = viaAi.evidence;
                }
            }
        }
        Found f = findByRules(c, d, fieldType, opts);
        if (aiNote != null) {
            f.aiNote = aiNote;
            f.evidence = (aiNote + ' ' + (f.evidence == null ? '' : f.evidence)).trim().left(255);
        }
        return f;
    }

    /** The AI's suggestion fitted to the field: text as is, picklist / lookup matched (directly or through Match Rules). */
    private Found fromAi(FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts, String suggested) {
        Found f = new Found();
        f.source = AI_SOURCE;
        f.exact = false;
        String shown = suggested.left(80);
        if (opts != null) {
            Option o = matchOption(opts, suggested, true);
            if (o == null) {
                String ruled = applyRulesTo(c.matchRules, suggested);
                if (ruled != null) {
                    o = matchOption(opts, ruled, true);
                    if (o == null && fieldType == 'reference') {
                        o = findRecord(d, ruled);
                    }
                }
            }
            if (o == null) {
                f.evidence = 'AI suggested "' + shown + '", which is not a value of this field.';
                return f;
            }
            f.value = o.value;
            f.display = o.label;
            f.evidence = ('Suggested by AI from the document ("' + shown + '"). Check it before you accept.').left(255);
            return f;
        }
        String v = fit(suggested, d, fieldType);
        if (v == null) {
            f.evidence = 'AI suggested "' + shown + '", which does not fit this field.';
            return f;
        }
        f.value = v;
        f.display = fieldType == 'date' ? displayDate(v) : null;
        f.evidence = 'Written by AI from the document. Check it before you accept.';
        return f;
    }

    /** The category whose template sections are found in the document (Category Templates headings). */
    private Found bestFitCategory(List<Option> opts) {
        DocPdfNumbering.BestFit bf = DocPdfNumbering.bestFit(text);
        if (bf == null) {
            return null;
        }
        Option o = matchOption(opts, bf.category, true);
        if (o == null) {
            return null;
        }
        Found f = new Found();
        f.value = o.value;
        f.display = o.label;
        f.source = BEST_FIT_SOURCE;
        f.evidence = ('Best-fit template: ' + bf.describe() + '.').left(255);
        return f;
    }

    /** The Template follows the Category: the released template set up for it in Category Templates. */
    private Found templateFromCategory(FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts) {
        DocPdfNumbering.CategoryTemplate ct = DocPdfNumbering.forCategory(categoryValue);
        if (ct == null || String.isBlank(ct.templateNumber)) {
            Found none = new Found();
            none.source = FROM_CATEGORY_SOURCE;
            none.evidence = ('No template is set up for Category ' + categoryValue
                + ' (Category Templates on Doc PDF Agent Setting), so the Document Number below is used.').left(255);
            return none;
        }
        DocPdfNumbering.Template t = DocPdfNumbering.releasedTemplate(ct.templateNumber);
        Found f = new Found();
        f.source = FROM_CATEGORY_SOURCE;
        if (t == null) {
            f.evidence = ('Template ' + ct.templateNumber + ' for Category ' + categoryValue
                + ' is not released (Current), so the Document Number below is used.').left(255);
            return f;
        }
        f.value = t.id;
        f.display = t.name;
        f.exact = true;
        f.evidence = ('Template for Category ' + categoryValue + '. If you change the Category, the template follows it.').left(255);
        return f;
    }

    /** The Document Number row: numbered by the template, else the category prefix plus the next free number. */
    private void addNumberRow() {
        Schema.SObjectField nf = cdFields.get(NUMBER_FIELD);
        if (nf == null || !nf.getDescribe().isCreateable()) {
            return;
        }
        String prefix = DocPdfNumbering.prefixFor(categoryValue);
        String suggested = DocPdfNumbering.nextNumber(prefix);
        String evidence;
        if (templateChosen != null) {
            evidence = 'Next free ' + prefix + ' number (template ' + templateChosen.label + '). ComplianceQuest numbers '
                + 'the document instead when its auto-numbering is set up.';
        } else {
            evidence = 'No released template for ' + (categoryValue == null ? 'this document' : 'Category ' + categoryValue)
                + ': next free ' + prefix + ' number. Edit it if you need to; it is checked again when you submit.';
        }
        addRow(nf.getDescribe().getName(), 'Document Number', 'review', NUMBER_SOURCE, 'string', suggested, null,
            evidence.left(255), false, null, 'accept');
    }

    private Found findByRules(FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts) {
        Found f = new Found();
        String src = c.source;
        String labelText = String.isBlank(c.pdfLabel) ? null : c.pdfLabel.trim().removeEnd(':');

        if (src == 'Fixed_Value') {
            setFromDefault(f, c, d, fieldType, opts);
            if (f.value != null) {
                f.exact = true;
                f.evidence = 'Fixed value.';
            }
            return f;
        }
        if (src == 'User_Input') {
            f.evidence = 'Not read from the file. Pick or enter a value.';
            return f;
        }
        if (src == 'Section_First_Sentence' || src == 'Section_Text') {
            if (labelText == null) {
                f.evidence = 'No section heading is set up for this field.';
                return f;
            }
            // Several headings may be given, separated by ; (the first one found is used).
            Boolean longField = d.getLength() >= 1000 || fieldType == 'textarea';
            for (String heading : labelText.split(';')) {
                heading = heading.trim().removeEnd(':');
                if (String.isBlank(heading)) {
                    continue;
                }
                String body = DocPdfFieldParser.sectionText(text, heading);
                String v = src == 'Section_First_Sentence'
                    ? (longField ? firstSentencesOf(body, 3, 500) : DocPdfFieldParser.firstSentenceOf(body, 600))
                    : body;
                if (String.isNotBlank(v)) {
                    f.value = fit(v, d, fieldType);
                    f.source = 'From document text';
                    f.evidence = (src == 'Section_First_Sentence' ? (longField ? 'First sentences of the ' : 'First sentence of the ') : 'The ')
                        + heading + ' section.';
                    return f;
                }
            }
            f.evidence = 'No ' + labelText.replace(';', ' or') + ' section was found.';
            return fallbackToDefault(f, c, d, fieldType, opts);
        }

        // Labeled_Value, Picklist_Match, Lookup_Match: start from the labeled value.
        String raw = labelText == null ? null : DocPdfFieldParser.labeledValue(text, labelText);
        if (src == 'Picklist_Match' || (src == 'Labeled_Value' && fieldType == 'picklist')) {
            if (String.isNotBlank(raw)) {
                Option o = matchOption(opts, raw, true);
                if (o != null) {
                    f.value = o.value;
                    f.display = o.label;
                    f.exact = true;
                    f.evidence = 'The file says "' + raw.left(80) + '".';
                    return f;
                }
                f.evidence = 'The file says "' + raw.left(80) + '", which is not a value of this field.';
            } else {
                f.evidence = labelText == null ? 'No file label is set up.' : 'No "' + labelText + ':" label in the file.';
            }
            // Document Category: the template whose sections the document has, before the keyword rules.
            if (d.getName().toLowerCase() == CATEGORY_FIELD) {
                Found byTemplate = bestFitCategory(opts);
                if (byTemplate != null) {
                    return byTemplate;
                }
            }
            String ruled = applyRules(c.matchRules);
            if (ruled != null) {
                Option o = matchOption(opts, ruled, true);
                if (o != null) {
                    f.value = o.value;
                    f.display = o.label;
                    f.source = 'By rule';
                    f.evidence = (f.evidence + ' Suggested by rule.').left(255);
                    return f;
                }
            }
            return fallbackToDefault(f, c, d, fieldType, opts);
        }
        if (src == 'Lookup_Match' || (src == 'Labeled_Value' && fieldType == 'reference')) {
            if (String.isNotBlank(raw)) {
                Option exact = matchOption(opts, raw, true);
                if (exact != null) {
                    f.value = exact.value;
                    f.display = exact.label;
                    f.exact = true;
                    f.evidence = 'The file says "' + raw.left(80) + '".';
                    return f;
                }
                Option close = matchOption(opts, raw, false);
                if (close != null) {
                    f.value = close.value;
                    f.display = close.label;
                    f.evidence = 'The file says "' + raw.left(80) + '". Closest match: ' + close.label + '.';
                    return f;
                }
                f.evidence = 'The file says "' + raw.left(80) + '", but no record has that name.';
            } else {
                f.evidence = labelText == null ? 'No file label is set up.' : 'No "' + labelText + ':" label in the file.';
            }
            String ruledRecord = applyRules(c.matchRules);
            if (ruledRecord != null) {
                Option o = matchOption(opts, ruledRecord, true);
                if (o == null) {
                    o = findRecord(d, ruledRecord);
                }
                if (o != null) {
                    f.value = o.value;
                    f.display = o.label;
                    f.source = 'By rule';
                    f.evidence = ('Suggested by rule (' + ruledRecord.left(60) + ').').left(255);
                    return f;
                }
                f.evidence = (f.evidence + ' The rule suggested "' + ruledRecord.left(60) + '", but no record has that name.').left(255);
            }
            return fallbackToDefault(f, c, d, fieldType, opts);
        }

        // Labeled_Value for text, date, number and checkbox fields.
        if (String.isNotBlank(raw)) {
            String v = fit(raw, d, fieldType);
            if (v != null) {
                f.value = v;
                f.display = fieldType == 'date' ? displayDate(v) : null;
                f.exact = true;
                f.evidence = 'From the "' + labelText + ':" label in the file.';
                return f;
            }
            f.evidence = 'The file says "' + raw.left(80) + '", which does not fit this field.';
        } else {
            f.evidence = labelText == null ? 'No file label is set up.' : 'No "' + labelText + ':" label in the file.';
        }
        return fallbackToDefault(f, c, d, fieldType, opts);
    }

    private Found fallbackToDefault(Found f, FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts) {
        if (String.isBlank(c.defaultValue)) {
            return f;
        }
        String why = f.evidence;
        if (c.defaultValue.trim().toLowerCase() == FIRST_LINE_TOKEN) {
            String line = opts == null ? fit(DocPdfFieldParser.firstLineOf(text), d, fieldType) : null;
            if (line != null) {
                f.value = line;
                f.display = null;
                f.source = 'From PDF text';
                f.exact = false;
                f.evidence = ((why == null ? '' : why + ' ') + 'Used the first line of the file.').left(255);
            }
            return f;
        }
        setFromDefault(f, c, d, fieldType, opts);
        if (f.value != null) {
            f.source = 'Default';
            f.exact = false;
            f.evidence = ((why == null ? '' : why + ' ') + 'Using the default.').left(255);
        }
        return f;
    }

    private void setFromDefault(Found f, FieldConfig c, Schema.DescribeFieldResult d, String fieldType, List<Option> opts) {
        String v = c.defaultValue == null ? null : c.defaultValue.trim();
        if (String.isBlank(v)) {
            f.evidence = 'No default value is set up.';
            return;
        }
        if (opts != null) {
            Option o = matchOption(opts, v, true);
            if (o == null && fieldType == 'reference') {
                // A record Id given as the default.
                for (Option x : opts) {
                    if (x.value != null && x.value.left(15) == v.left(15)) {
                        o = x;
                        break;
                    }
                }
            }
            if (o == null) {
                f.evidence = 'The default "' + v.left(80) + '" is not a value of this field.';
                return;
            }
            f.value = o.value;
            f.display = o.label;
            return;
        }
        f.value = fit(v, d, fieldType);
        f.display = fieldType == 'date' && f.value != null ? displayDate(f.value) : null;
        if (f.value == null) {
            f.evidence = 'The default "' + v.left(80) + '" does not fit this field.';
        }
    }

    /** The value of the first Match Rule (regex => value) whose pattern is found in the PDF text. */
    @TestVisible
    private String applyRules(String rules) {
        return applyRulesTo(rules, text);
    }

    /** The value of the first Match Rule (regex => value) whose pattern is found in the given text. */
    @TestVisible
    private String applyRulesTo(String rules, String subject) {
        if (String.isBlank(rules) || String.isBlank(subject)) {
            return null;
        }
        for (String line : rules.split('\n')) {
            if (!line.contains('=>')) {
                continue;
            }
            String regex = line.substringBefore('=>').trim();
            String value = line.substringAfter('=>').trim();
            if (String.isBlank(regex) || String.isBlank(value)) {
                continue;
            }
            try {
                if (Pattern.compile(regex).matcher(subject).find()) {
                    return value;
                }
            } catch (Exception e) {
                skipped.add('rule "' + regex.left(40) + '" (' + e.getMessage().left(60) + ')');
            }
        }
        return null;
    }

    /** Converts text from the PDF to the stored form of the field; null when it does not fit. */
    private static String fit(String v, Schema.DescribeFieldResult d, String fieldType) {
        if (v == null) {
            return null;
        }
        v = v.trim();
        if (fieldType == 'date') {
            return DocPdfFieldParser.isoDate(v);
        }
        if (fieldType == 'boolean') {
            String l = v.toLowerCase();
            return (l == 'true' || l == 'yes' || l == 'y') ? 'true' : (l == 'false' || l == 'no' || l == 'n') ? 'false' : null;
        }
        if (fieldType == 'number') {
            String n = v.replaceAll('[^0-9.\\-]', '');
            return n.isNumeric() || Pattern.matches('-?\\d*\\.?\\d+', n) ? n : null;
        }
        Integer max = d.getLength();
        return max > 0 && v.length() > max ? v.left(max) : v;
    }

    private static String typeOf(Schema.DescribeFieldResult d) {
        Schema.DisplayType t = d.getType();
        if (t == Schema.DisplayType.PICKLIST) { return 'picklist'; }
        if (t == Schema.DisplayType.REFERENCE) { return 'reference'; }
        if (t == Schema.DisplayType.DATE) { return 'date'; }
        if (t == Schema.DisplayType.BOOLEAN) { return 'boolean'; }
        if (t == Schema.DisplayType.TEXTAREA) { return 'textarea'; }
        if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.INTEGER
            || t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) { return 'number'; }
        return 'string';
    }

    // ------------------------------------------------------------------ options

    private List<Option> picklistOptions(Schema.DescribeFieldResult d) {
        List<Option> opts = new List<Option>();
        for (Schema.PicklistEntry e : d.getPicklistValues()) {
            if (e.isActive()) {
                opts.add(new Option(e.getValue(), e.getLabel(), null));
            }
        }
        return opts;
    }

    private List<Option> recordTypeOptions() {
        List<Option> opts = new List<Option>();
        for (Schema.RecordTypeInfo rt : compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (rt.isAvailable() && !rt.isMaster()) {
                opts.add(new Option(rt.getRecordTypeId(), rt.getName(), rt.getDeveloperName()));
            }
        }
        return opts;
    }

    /** Up to 200 records of the looked-up object, by Name, that the user can see. */
    private List<Option> lookupOptions(Schema.DescribeFieldResult d) {
        List<Option> opts = new List<Option>();
        List<Schema.SObjectType> targets = d.getReferenceTo();
        if (targets.isEmpty()) {
            return opts;
        }
        // Owner-style fields point at Group and User: offer users.
        Schema.SObjectType targetType = targets[0];
        for (Schema.SObjectType t : targets) {
            if (t == User.SObjectType) {
                targetType = t;
            }
        }
        Schema.DescribeSObjectResult target = targetType.getDescribe();
        if (!target.fields.getMap().containsKey('name') || !target.isAccessible()) {
            return opts;
        }
        Boolean isDoc = targetType == compliancequest__SQX_Controlled_Document__c.SObjectType;
        String whereClause = targetType == User.SObjectType ? ' WHERE IsActive = true'
            : isTemplateField(d) ? ' WHERE RecordType.DeveloperName = \'Template_Document\' AND compliancequest__Document_Status__c = \'Current\'' : '';
        String soql = 'SELECT Id, Name' + (isDoc ? ', compliancequest__Document_Number__c' : '') + ' FROM ' + target.getName()
            + whereClause + ' ORDER BY Name LIMIT 200';
        for (SObject r : Database.query(soql, AccessLevel.USER_MODE)) {
            opts.add(new Option(r.Id, (String) r.get('Name'),
                isDoc ? (String) r.get('compliancequest__Document_Number__c') : null));
        }
        return opts;
    }

    /** The Controlled Document Template field: offer Template Document records only. */
    private static Boolean isTemplateField(Schema.DescribeFieldResult d) {
        return d.getName().toLowerCase() == TEMPLATE_FIELD;
    }

    /** One record of the looked-up object named (or, for Controlled Documents, numbered) as given; null if none. */
    @TestVisible
    private Option findRecord(Schema.DescribeFieldResult d, String nameOrNumber) {
        List<Schema.SObjectType> targets = d.getReferenceTo();
        if (targets.isEmpty() || String.isBlank(nameOrNumber)) {
            return null;
        }
        Schema.SObjectType targetType = targets[0];
        for (Schema.SObjectType t : targets) {
            if (t == User.SObjectType) {
                targetType = t;
            }
        }
        if (!targetType.getDescribe().isAccessible() || !targetType.getDescribe().fields.getMap().containsKey('name')) {
            return null;
        }
        String v = nameOrNumber.trim();
        Boolean isDoc = targetType == compliancequest__SQX_Controlled_Document__c.SObjectType;
        String soql = 'SELECT Id, Name' + (isDoc ? ', compliancequest__Document_Number__c' : '')
            + ' FROM ' + targetType.getDescribe().getName()
            + ' WHERE (Name = :v' + (isDoc ? ' OR compliancequest__Document_Number__c = :v' : '') + ')'
            + (isDoc && isTemplateField(d) ? ' AND RecordType.DeveloperName = \'Template_Document\' AND compliancequest__Document_Status__c = \'Current\'' : '')
            + ' ORDER BY Name DESC LIMIT 1';
        List<SObject> found = Database.queryWithBinds(soql, new Map<String, Object>{ 'v' => v }, AccessLevel.USER_MODE);
        if (found.isEmpty()) {
            return null;
        }
        return new Option(found[0].Id, (String) found[0].get('Name'),
            isDoc ? (String) found[0].get('compliancequest__Document_Number__c') : null);
    }

    /** Exact: value or label equals (ignoring case, or a record type developer name). Else: one contains the other. */
    @TestVisible
    private static Option matchOption(List<Option> opts, String wanted, Boolean exact) {
        if (opts == null || String.isBlank(wanted)) {
            return null;
        }
        String w = wanted.trim().toLowerCase();
        for (Option o : opts) {
            if ((o.value != null && o.value.toLowerCase() == w) || (o.label != null && o.label.toLowerCase() == w)
                || (o.detail != null && o.detail.toLowerCase() == w)) {
                return o;
            }
        }
        if (exact) {
            return null;
        }
        for (Option o : opts) {
            String l = o.label == null ? '' : o.label.toLowerCase();
            if (l.length() >= 3 && (w.contains(l) || l.contains(w))) {
                return o;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ helpers

    private void addRow(String apiName, String label, String section, String source, String fieldType,
                        String value, String display, String evidence, Boolean required,
                        List<Option> options, String decision) {
        sortOrder += 10;
        rows.add(new Doc_PDF_Field__c(
            Proposal__c = proposalId,
            Field_API_Name__c = apiName,
            Field_Label__c = label == null ? apiName : label.left(100),
            Section__c = section,
            Source__c = source,
            Field_Type__c = fieldType,
            Proposed_Value__c = value,
            Proposed_Display__c = display == null ? (value == null ? null : value.left(255)) : display.left(255),
            Decision__c = decision,
            Evidence__c = evidence == null ? null : evidence.left(255),
            Required__c = required == true,
            Options_JSON__c = optionsJson(options),
            Sort_Order__c = sortOrder
        ));
    }

    /** Options as JSON, dropping options from the end so it fits the 32,768-character field. */
    private static String optionsJson(List<Option> options) {
        if (options == null || options.isEmpty()) {
            return null;
        }
        List<Option> kept = new List<Option>(options);
        String serialized = JSON.serialize(kept);
        while (serialized.length() > 32000 && kept.size() > 1) {
            kept.remove(kept.size() - 1);
            serialized = JSON.serialize(kept);
        }
        return serialized.length() > 32000 ? null : serialized;
    }

    @TestVisible
    private static String defaultDecision(String section, String value) {
        if (section == 'system') { return 'locked'; }
        if (section == 'optional') { return 'clear'; }
        if (section == 'ready') { return value == null ? 'clear' : 'accept'; }
        return 'undecided';
    }

    /** Up to n whole sentences from the start of s, within maxLen characters (at least the first sentence). */
    @TestVisible
    private static String firstSentencesOf(String s, Integer n, Integer maxLen) {
        if (String.isBlank(s)) {
            return null;
        }
        String flat = s.normalizeSpace();
        String out = '';
        Integer start = 0;
        for (Integer i = 0; i < n && start < flat.length(); i++) {
            Integer cut = flat.indexOf('. ', start);
            String next = cut < 0 ? flat.substring(start) : flat.substring(start, cut + 1);
            String candidate = (out + ' ' + next).trim();
            if (out.length() > 0 && candidate.length() > maxLen) {
                break;
            }
            out = candidate;
            if (cut < 0) {
                break;
            }
            start = cut + 2;
        }
        if (out.length() > maxLen) {
            out = out.substring(0, maxLen - 1).trim() + '…';
        }
        return out.trim();
    }

    private static String displayDate(String iso) {
        try {
            return Date.valueOf(iso).format();
        } catch (Exception e) {
            return iso;
        }
    }

    private static String nvl(String s, String fallback) {
        return String.isBlank(s) ? fallback : s;
    }
}
