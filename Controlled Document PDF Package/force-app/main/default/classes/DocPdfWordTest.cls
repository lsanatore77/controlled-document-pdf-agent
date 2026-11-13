/**
 * Tests for Word (.docx) reading (DocPdfDocxReader, GoogleVisionPdfService routing) and
 * category-driven template and numbering (DocPdfNumbering, builder Document Number row,
 * DocPdfCreateDocumentAction.planNumber).
 */
@IsTest
private class DocPdfWordTest {

    private static final String W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
    private static final String MC = 'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"';

    private static final String LINES =
        'Policy | TMP-POL-000 | POL | Policy Purpose; Principles of this Policy; Definitions; Related\n' +
        'Procedure | TMP-PROC-000 | PROC | Summary; Requirements; Procedures; Validation\n' +
        'Work Instruction | TMP-WI-000 | WI | Objective; Scope; Required Personal Protective Equipment (PPE); Procedure; Emergency Procedures\n' +
        '# a comment line\n' +
        'SOP | | SOP |';

    private static String p(String text) {
        return '<w:p><w:r><w:t xml:space="preserve">' + text + '</w:t></w:r></w:p>';
    }

    private static String documentXml() {
        return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            + '<w:document ' + W + ' ' + MC + '><w:body>'
            + p('Hand Washing Work Instruction')
            + p('Objective')
            + '<w:p><w:r><w:t>Keep hands clean.</w:t></w:r><w:r><w:tab/><w:t>Always.</w:t></w:r></w:p>'
            + '<w:p><w:del><w:r><w:delText>removed words</w:delText></w:r></w:del><w:ins><w:r><w:t>Added words.</w:t></w:r></w:ins></w:p>'
            + p('Scope')
            + '<w:tbl><w:tr><w:tc>' + p('Step') + '</w:tc><w:tc>' + p('Task') + '</w:tc></w:tr>'
            + '<w:tr><w:tc>' + p('1') + '</w:tc><w:tc>' + p('Wet hands') + p('with water') + '</w:tc></w:tr></w:tbl>'
            + '<w:p><w:r><mc:AlternateContent><mc:Choice><w:t>Box text</w:t></mc:Choice>'
            + '<mc:Fallback><w:t>Box text</w:t></mc:Fallback></mc:AlternateContent></w:r></w:p>'
            + p('Procedure')
            + '<w:p><w:r><w:t>Line one</w:t><w:br/><w:t>Line two</w:t></w:r></w:p>'
            + '</w:body></w:document>';
    }

    private static Blob docx(String xml) {
        Compression.ZipWriter zw = new Compression.ZipWriter();
        zw.addEntry('[Content_Types].xml', Blob.valueOf('<Types/>'));
        if (xml != null) {
            zw.addEntry('word/document.xml', Blob.valueOf(xml));
        }
        return zw.getArchive();
    }

    private static User appUser() {
        User me = new User(Id = UserInfo.getUserId());
        System.runAs(me) {
            List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'Doc_From_PDF_Agent_Access' LIMIT 1];
            if (!ps.isEmpty() && [
                SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :me.Id AND PermissionSetId = :ps[0].Id
            ] == 0) {
                insert new PermissionSetAssignment(AssigneeId = me.Id, PermissionSetId = ps[0].Id);
            }
        }
        return me;
    }

    // ------------------------------------------------------------------ Word reading

    @IsTest
    static void readsParagraphsTablesAndTrackedChanges() {
        String t = DocPdfDocxReader.readText(docx(documentXml()));
        List<String> lines = t.split('\n');
        Assert.areEqual('Hand Washing Work Instruction', lines[0]);
        Assert.isTrue(t.contains('Keep hands clean.\tAlways.'), t);
        Assert.isTrue(t.contains('Added words.'), t);
        Assert.isFalse(t.contains('removed words'), 'Deleted text is skipped: ' + t);
        Assert.isTrue(t.contains('Step\tTask'), t);
        Assert.isTrue(t.contains('1\tWet hands with water'), t);
        Assert.areEqual(1, t.countMatches('Box text'), 'Text boxes are read once: ' + t);
        Assert.isTrue(t.contains('Line one\nLine two'), t);
    }

    @IsTest
    static void explainsFilesItCannotRead() {
        try {
            DocPdfDocxReader.readText(docx(null));
            Assert.fail('A zip without word/document.xml is not a Word file.');
        } catch (DocPdfDocxReader.ReadException e) {
            Assert.isTrue(e.getMessage().contains('Word'), e.getMessage());
        }
        try {
            DocPdfDocxReader.readText(Blob.valueOf('not a zip'));
            Assert.fail('Not a zip.');
        } catch (DocPdfDocxReader.ReadException e) {
            Assert.isTrue(e.getMessage().contains('could not be opened'), e.getMessage());
        }
        try {
            DocPdfDocxReader.readText(null);
            Assert.fail('Empty.');
        } catch (DocPdfDocxReader.ReadException e) {
            Assert.isTrue(e.getMessage().contains('empty'), e.getMessage());
        }
        Assert.isTrue(DocPdfDocxReader.isSupported('PDF'));
        Assert.isTrue(DocPdfDocxReader.isSupported('WORD_X'));
        Assert.isFalse(DocPdfDocxReader.isSupported('WORD'));
        Assert.isTrue(DocPdfDocxReader.unsupportedMessage('Old', 'WORD').contains('.docx'));
        Assert.isTrue(DocPdfDocxReader.unsupportedMessage(null, 'PNG').contains('PDF or a Word'));
    }

    @IsTest
    static void extractRoutesWordFilesToApex() {
        ContentVersion cv = new ContentVersion(Title = 'Hand Washing', PathOnClient = 'Hand Washing.docx',
            VersionData = docx(documentXml()));
        insert cv;
        GoogleVisionPdfService.Extraction ex = GoogleVisionPdfService.extract(cv.Id);
        Assert.isTrue(ex.success, '' + ex.message);
        Assert.isTrue(ex.isWord);
        Assert.areEqual(1, ex.pagesRead);
        Assert.isTrue(ex.text.startsWith('Hand Washing Work Instruction'), ex.text);

        DocPdfDocxReader.MAX_BYTES = 10;
        GoogleVisionPdfService.Extraction big = GoogleVisionPdfService.extract(cv.Id);
        Assert.isFalse(big.success);
        Assert.isTrue(big.message.contains('too large'), big.message);

        ContentVersion png = new ContentVersion(Title = 'Picture', PathOnClient = 'Picture.png', VersionData = Blob.valueOf('x'));
        insert png;
        GoogleVisionPdfService.Extraction other = GoogleVisionPdfService.extract(png.Id);
        Assert.isFalse(other.success);
        Assert.isTrue(other.message.contains('not a PDF or a Word'), other.message);
    }

    @IsTest
    static void selectAcceptsWordFiles() {
        System.runAs(appUser()) {
            ContentVersion cv = new ContentVersion(Title = 'Hand Washing', PathOnClient = 'Hand Washing.docx',
                VersionData = docx(documentXml()));
            insert cv;
            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            DocPdfFileSelection s = new DocPdfFileSelection();
            s.contentDocumentId = docId;
            DocPdfSelectFileAction.Result r = DocPdfSelectFileAction.runOne(s);
            Assert.isTrue(r.success, r.message);
        }
    }

    // ------------------------------------------------------------------ numbering

    @IsTest
    static void readsCategoryTemplates() {
        DocPdfNumbering.testLines = LINES;
        List<DocPdfNumbering.CategoryTemplate> all = DocPdfNumbering.load();
        Assert.areEqual(4, all.size());
        DocPdfNumbering.CategoryTemplate wi = DocPdfNumbering.forCategory('work instruction');
        Assert.areEqual('TMP-WI-000', wi.templateNumber);
        Assert.areEqual(5, wi.headings.size());
        Assert.isNull(DocPdfNumbering.forCategory('SOP').templateNumber);
        Assert.isNull(DocPdfNumbering.forCategory('Form'));
        Assert.isNull(DocPdfNumbering.forCategory(null));

        Assert.areEqual('POL', DocPdfNumbering.prefixFor('Policy'));
        Assert.areEqual('SOP', DocPdfNumbering.prefixFor('SOP'));
        Assert.areEqual('QM', DocPdfNumbering.prefixFor('Quality Manual'));
        Assert.areEqual('FOR', DocPdfNumbering.prefixFor('Form'));
        Assert.areEqual('DOC', DocPdfNumbering.prefixFor(''));
        Assert.isNull(DocPdfNumbering.templateForCategory('SOP'));
        Assert.isNull(DocPdfNumbering.releasedTemplate(null));
    }

    @IsTest
    static void suggestsTheNextFreeNumber() {
        Assert.areEqual('POL-000001', DocPdfNumbering.format('POL', 1));
        Assert.areEqual('ZZQ-000001', DocPdfNumbering.nextNumber('zzq'));
        Assert.isFalse(DocPdfNumbering.isTaken('ZZQ-000001'));
        Assert.isFalse(DocPdfNumbering.isTaken(null));
        Assert.areEqual('ZZQ-000007', DocPdfNumbering.freeNumber('ZZQ-000007', 'ZZQ'));
        Assert.areEqual('ZZQ-000001', DocPdfNumbering.freeNumber(null, 'ZZQ'));
    }

    @IsTest
    static void picksTheBestFitTemplateFromHeadings() {
        DocPdfNumbering.testLines = LINES;
        String text = 'Hand Washing\nObjective\nKeep hands clean.\n2. Scope\nAll staff.\n'
            + 'Required Personal Protective Equipment (PPE)\nGloves\nProcedure\nWet hands.';
        DocPdfNumbering.BestFit bf = DocPdfNumbering.bestFit(text);
        Assert.areEqual('Work Instruction', bf.category);
        Assert.areEqual(4, bf.found);
        Assert.isTrue(bf.describe().contains('4 of 5'), bf.describe());

        String policy = 'cGMP\nPOLICY PURPOSE\nWhy.\nPRINCIPLES OF THIS POLICY:\nHow.\nDEFINITIONS\nTerms.';
        Assert.areEqual('Policy', DocPdfNumbering.bestFit(policy).category);
        Assert.isNull(DocPdfNumbering.bestFit('Just a letter.\nProcedure\nNothing else.'));
        Assert.isNull(DocPdfNumbering.bestFit(null));
        Assert.isNull(DocPdfNumbering.normalizeHeading('   '));
        Assert.areEqual('purpose', DocPdfNumbering.normalizeHeading('1.2) Purpose:'));
    }

    @IsTest
    static void builderAddsBestFitCategoryAndNumberRow() {
        System.runAs(appUser()) {
            DocPdfNumbering.testLines = LINES;
            DocPdfAiSuggestions.testTemplate = '';
            DocPdfRecommendationBuilder.FieldConfig cat = new DocPdfRecommendationBuilder.FieldConfig();
            cat.apiName = 'compliancequest__Document_Category__c';
            cat.source = 'Picklist_Match';
            cat.pdfLabel = 'Document Category';
            cat.aiAnswer = 'documentType';
            DocPdfRecommendationBuilder.FieldConfig tmpl = new DocPdfRecommendationBuilder.FieldConfig();
            tmpl.apiName = 'compliancequest__Document_Type__c';
            tmpl.source = 'Lookup_Match';
            tmpl.sortOrder = 35;
            DocPdfRecommendationBuilder.FieldConfig descr = new DocPdfRecommendationBuilder.FieldConfig();
            descr.apiName = 'compliancequest__Description__c';
            descr.source = 'Section_First_Sentence';
            descr.pdfLabel = 'Purpose; Objective';
            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{ cat, tmpl, descr };

            Doc_PDF_Proposal__c prop = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'Hand Washing');
            insert prop;
            String text = 'Hand Washing\nObjective\nKeep hands clean. Use soap. Dry well. Then leave.\nScope\nAll staff.\n'
                + 'Required Personal Protective Equipment (PPE)\nGloves\nProcedure\nWet hands.';
            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(prop.Id, text, 1, 1, true, null);
            Assert.isTrue(s.success, s.message);
            Assert.isTrue(s.message.startsWith('I read Hand Washing.'), s.message);

            Map<String, Doc_PDF_Field__c> rows = new Map<String, Doc_PDF_Field__c>();
            for (Doc_PDF_Field__c f : [
                SELECT Field_API_Name__c, Proposed_Value__c, Source__c, Evidence__c, Decision__c, Section__c
                FROM Doc_PDF_Field__c WHERE Proposal__c = :prop.Id
            ]) {
                rows.put(f.Field_API_Name__c, f);
            }
            Doc_PDF_Field__c c = rows.get('compliancequest__Document_Category__c');
            if (c.Proposed_Value__c != null) {
                // Only when the org's Category picklist has Work Instruction.
                Assert.areEqual('Work Instruction', c.Proposed_Value__c);
                Assert.areEqual(DocPdfRecommendationBuilder.BEST_FIT_SOURCE, c.Source__c);
            }
            Doc_PDF_Field__c n = rows.get('compliancequest__Document_Number__c');
            Assert.isNotNull(n, 'A Document Number row is added.');
            Assert.areEqual('accept', n.Decision__c);
            Assert.isTrue(n.Proposed_Value__c.endsWith('-000001') || n.Proposed_Value__c.contains('-'), n.Proposed_Value__c);
            Doc_PDF_Field__c t = rows.get('compliancequest__Document_Type__c');
            Assert.isNull(t.Proposed_Value__c, 'No released template in a test.');
            Doc_PDF_Field__c d = rows.get('compliancequest__Description__c');
            Assert.areEqual('Keep hands clean. Use soap. Dry well.', d.Proposed_Value__c);
        }
    }

    @IsTest
    static void namesADocumentLeftWithItsId() {
        Id fakeId = UserInfo.getUserId();
        compliancequest__SQX_Controlled_Document__c d = (compliancequest__SQX_Controlled_Document__c)
            JSON.deserialize(JSON.serialize(new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'compliancequest__SQX_Controlled_Document__c' },
                'Name' => String.valueOf(fakeId).left(15),
                'compliancequest__Document_Number__c' => 'WI-000001',
                'compliancequest__Revision__c' => '001'
            }), compliancequest__SQX_Controlled_Document__c.class);
        // Without an Id the name is only checked for being blank or set.
        Assert.isNull(DocPdfCreateDocumentAction.nameFor(d));
        d.Name = null;
        Assert.areEqual('WI-000001[001]', DocPdfCreateDocumentAction.nameFor(d));
        d.compliancequest__Revision__c = null;
        Assert.areEqual('WI-000001', DocPdfCreateDocumentAction.nameFor(d));
        d.Name = 'WI-000001[001]';
        Assert.isNull(DocPdfCreateDocumentAction.nameFor(d));
        d.Name = null;
        d.compliancequest__Document_Number__c = null;
        Assert.isNull(DocPdfCreateDocumentAction.nameFor(d));
    }

    @IsTest
    static void planFollowsTheFinalCategory() {
        DocPdfNumbering.testLines = LINES;
        List<Doc_PDF_Field__c> rows = new List<Doc_PDF_Field__c>{
            new Doc_PDF_Field__c(Field_API_Name__c = 'compliancequest__Document_Category__c', Final_Value__c = 'Policy', Decision__c = 'edit'),
            new Doc_PDF_Field__c(Field_API_Name__c = 'compliancequest__Document_Type__c', Decision__c = 'clear'),
            new Doc_PDF_Field__c(Field_API_Name__c = 'compliancequest__Document_Number__c', Final_Value__c = 'WI-000003', Decision__c = 'accept')
        };
        DocPdfCreateDocumentAction.NumberPlan plan = DocPdfCreateDocumentAction.planNumber(rows);
        Assert.areEqual('POL', plan.prefix);
        Assert.isNull(plan.templateId, 'No released template in a test.');
        Assert.isNull(plan.wantedNumber, 'A number the user did not edit is worked out again from the final category.');

        rows[2].Decision__c = 'edit';
        rows[2].Final_Value__c = 'POL-000123';
        rows[1].Decision__c = 'edit';
        rows[1].Final_Value__c = UserInfo.getUserId();
        rows[1].Final_Display__c = 'Picked';
        plan = DocPdfCreateDocumentAction.planNumber(rows);
        Assert.areEqual('POL-000123', plan.wantedNumber);
        Assert.areEqual('Picked', plan.templateName);
    }

    @IsTest
    static void autoPlaceholderIsNotANumber() {
        // ComplianceQuest leaves AUTO when its auto-numbering has no Auto Number record: the category number is used.
        Assert.isTrue(DocPdfCreateDocumentAction.notNumbered(null));
        Assert.isTrue(DocPdfCreateDocumentAction.notNumbered(' '));
        Assert.isTrue(DocPdfCreateDocumentAction.notNumbered('AUTO'));
        Assert.isTrue(DocPdfCreateDocumentAction.notNumbered('auto '));
        Assert.isFalse(DocPdfCreateDocumentAction.notNumbered('POL-000001'));
        Assert.isFalse(DocPdfCreateDocumentAction.notNumbered('AUTO-000001'));
    }
}
