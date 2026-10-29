/**
 * Tests for AI suggestions (DocPdfAiSuggestions) with the rule fallback in
 * DocPdfRecommendationBuilder, the looser section headings and first-line title in
 * DocPdfFieldParser, and the clean retry record in DocPdfCreateDocumentAction.
 */
@IsTest
private class DocPdfAiTest {

    // A policy laid out without labels, like the cGMP Fundamentals PDF.
    private static final String POLICY =
        'Current Good Manufacturing Practices (cGMP) Fundamentals\n' +
        'POLICY PURPOSE\n' +
        'This document sets out the fundamental cGMP requirements the company follows so that every product is consistently produced and controlled.\n' +
        'cGMP exists to protect patients.\n' +
        'PRINCIPLES OF THIS POLICY\n' +
        'The company is committed to the following cGMP fundamentals.\n' +
        '1|Page\n' +
        'DEFINITIONS\nBatch (Lot) A specific quantity of material.';

    private static final String RULES =
        '(?i)\\bwork instruction\\b => Work Instruction\n' +
        '(?im)^\\s*policy purpose\\b => Policy\n' +
        '(?i)\\bpolicy\\b => Policy';

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

    private static DocPdfRecommendationBuilder.FieldConfig cfg(String api, String source, String pdfLabel,
                                                               String defaultValue, String rules, String aiAnswer) {
        DocPdfRecommendationBuilder.FieldConfig c = new DocPdfRecommendationBuilder.FieldConfig();
        c.apiName = api;
        c.required = false;
        c.editable = true;
        c.source = source;
        c.pdfLabel = pdfLabel;
        c.defaultValue = defaultValue;
        c.matchRules = rules;
        c.aiAnswer = aiAnswer;
        return c;
    }

    private static void useConfig() {
        DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
            cfg('compliancequest__Title__c', 'Labeled_Value', 'Title', '{First Line}', null, 'title'),
            cfg('compliancequest__Description__c', 'Section_First_Sentence', 'Purpose', null, null, 'description'),
            cfg('compliancequest__Document_Category__c', 'Picklist_Match', 'Document Category', null, RULES, 'documentType')
        };
    }

    private static Map<String, Doc_PDF_Field__c> rowsOf(Id proposalId) {
        Map<String, Doc_PDF_Field__c> byApi = new Map<String, Doc_PDF_Field__c>();
        for (Doc_PDF_Field__c f : [
            SELECT Field_API_Name__c, Section__c, Proposed_Value__c, Source__c, Evidence__c
            FROM Doc_PDF_Field__c WHERE Proposal__c = :proposalId
        ]) {
            byApi.put(f.Field_API_Name__c, f);
        }
        return byApi;
    }

    // ------------------------------------------------------------------ AI answer parsing

    @IsTest
    static void parsesTheJsonAnswer() {
        Map<String, String> m = DocPdfAiSuggestions.parse(
            'Here it is:\n```json\n{"title": "cGMP Fundamentals", "Description": "Sets out cGMP rules.", "documentType": "Policy", "extra": null}\n```');
        Assert.areEqual('cGMP Fundamentals', m.get('title'));
        Assert.areEqual('Sets out cGMP rules.', m.get('description'));
        Assert.areEqual('Policy', m.get('documenttype'));
        Assert.isFalse(m.containsKey('extra'));
        Assert.isTrue(DocPdfAiSuggestions.parse('no json here').isEmpty());
        Assert.isTrue(DocPdfAiSuggestions.parse('{not valid').isEmpty());
        Assert.isTrue(DocPdfAiSuggestions.parse('[1,2]').isEmpty());
        Assert.isTrue(DocPdfAiSuggestions.parse(null).isEmpty());
    }

    @IsTest
    static void reportsWhyAiWasOff() {
        DocPdfAiSuggestions.testTemplate = '';
        DocPdfAiSuggestions.Result off = DocPdfAiSuggestions.suggest(POLICY);
        Assert.isFalse(off.used);
        Assert.isTrue(off.status.contains('No Field Prompt Template'), off.status);

        DocPdfAiSuggestions.testTemplate = 'Doc_PDF_Field_Suggestions';
        DocPdfAiSuggestions.testAnswer = 'FAIL';
        DocPdfAiSuggestions.Result failed = DocPdfAiSuggestions.suggest(POLICY);
        Assert.isFalse(failed.used);
        Assert.isTrue(failed.status.contains('could not be run'), failed.status);

        DocPdfAiSuggestions.testAnswer = 'Sorry, I cannot help.';
        DocPdfAiSuggestions.Result unreadable = DocPdfAiSuggestions.suggest(POLICY);
        Assert.isFalse(unreadable.used);
        Assert.isTrue(unreadable.status.contains('could not be read'), unreadable.status);

        DocPdfAiSuggestions.testAnswer = '{"title":"T"}';
        Assert.isFalse(DocPdfAiSuggestions.suggest('').used);
        DocPdfAiSuggestions.Result ok = DocPdfAiSuggestions.suggest(POLICY);
        Assert.isTrue(ok.used);
        Assert.areEqual('T', ok.get('Title'));
        Assert.isTrue(ok.status.startsWith('AI suggestions: on'), ok.status);
    }

    // ------------------------------------------------------------------ builder: AI first, rules after

    @IsTest
    static void usesAiFirstAndShowsIt() {
        System.runAs(appUser()) {
            useConfig();
            DocPdfAiSuggestions.testTemplate = 'Doc_PDF_Field_Suggestions';
            DocPdfAiSuggestions.testAnswer =
                '{"title": "cGMP Fundamentals", "description": "Sets out the cGMP requirements every product must meet.", "documentType": "Policy"}';
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'cGMP.pdf');
            insert p;

            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(p.Id, POLICY, 3, 3, true, null);
            Assert.isTrue(s.success, '' + s.message);

            Map<String, Doc_PDF_Field__c> rows = rowsOf(p.Id);
            Doc_PDF_Field__c title = rows.get('compliancequest__Title__c');
            Assert.areEqual('cGMP Fundamentals', title.Proposed_Value__c);
            Assert.areEqual(DocPdfRecommendationBuilder.AI_SOURCE, title.Source__c);
            Assert.areEqual('review', title.Section__c, 'AI values are always left for review.');
            Assert.areEqual(DocPdfRecommendationBuilder.AI_SOURCE, rows.get('compliancequest__Description__c').Source__c);

            String status = [SELECT AI_Status__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id].AI_Status__c;
            Assert.isTrue(status.startsWith('AI suggestions: on'), status);
        }
    }

    @IsTest
    static void fallsBackToRulesWhenAiIsOff() {
        System.runAs(appUser()) {
            useConfig();
            DocPdfAiSuggestions.testTemplate = '';
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'cGMP.pdf');
            insert p;

            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(p.Id, POLICY, 3, 3, true, null);
            Assert.isTrue(s.success, '' + s.message);

            Map<String, Doc_PDF_Field__c> rows = rowsOf(p.Id);
            Doc_PDF_Field__c title = rows.get('compliancequest__Title__c');
            Assert.areEqual('Current Good Manufacturing Practices (cGMP) Fundamentals', title.Proposed_Value__c);
            Assert.areEqual('From PDF text', title.Source__c);
            Assert.isTrue(title.Evidence__c.contains('AI was off'), title.Evidence__c);
            Assert.isTrue(title.Evidence__c.contains('first line'), title.Evidence__c);

            Doc_PDF_Field__c descr = rows.get('compliancequest__Description__c');
            Assert.isTrue(descr.Proposed_Value__c.startsWith('This document sets out the fundamental cGMP'), descr.Proposed_Value__c);

            String status = [SELECT AI_Status__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id].AI_Status__c;
            Assert.isTrue(status.startsWith('AI suggestions: off'), status);
        }
    }

    @IsTest
    static void aiValuesThatDoNotFitFallBack() {
        System.runAs(appUser()) {
            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
                cfg('compliancequest__Document_Category__c', 'Picklist_Match', 'Document Category', null, RULES, 'documentType'),
                cfg('compliancequest__Effective_Date__c', 'Labeled_Value', 'Effective Date', null, null, 'title'),
                cfg('compliancequest__Description__c', 'Section_Text', 'Purpose', null, null, 'missingKey'),
                cfg('OwnerId', 'Lookup_Match', null, null, '(?i)\\bpolicy\\b => ' + UserInfo.getName(), 'documentType')
            };
            DocPdfAiSuggestions.testTemplate = 'Doc_PDF_Field_Suggestions';
            DocPdfAiSuggestions.testAnswer = '{"title": "not a date", "documentType": "Something Else"}';
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'cGMP.pdf');
            insert p;

            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(p.Id, POLICY, 3, 3, true, null);
            Assert.isTrue(s.success, '' + s.message);
            Map<String, Doc_PDF_Field__c> rows = rowsOf(p.Id);

            Doc_PDF_Field__c dateRow = rows.get('compliancequest__Effective_Date__c');
            Assert.isNull(dateRow.Proposed_Value__c);
            Assert.isTrue(dateRow.Evidence__c.contains('does not fit'), dateRow.Evidence__c);

            Doc_PDF_Field__c descr = rows.get('compliancequest__Description__c');
            Assert.isTrue(descr.Evidence__c.contains('AI gave no missingKey'), descr.Evidence__c);

            Doc_PDF_Field__c owner = rows.get('OwnerId');
            Assert.areEqual(UserInfo.getUserId(), Id.valueOf(owner.Proposed_Value__c), owner.Evidence__c);
            Assert.areEqual('By rule', owner.Source__c);
        }
    }

    @IsTest
    static void aiAnswerCanMapThroughTheRules() {
        System.runAs(appUser()) {
            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
                cfg('OwnerId', 'Lookup_Match', null, null, '(?i)^policy$ => ' + UserInfo.getName(), 'documentType')
            };
            DocPdfAiSuggestions.testTemplate = 'Doc_PDF_Field_Suggestions';
            DocPdfAiSuggestions.testAnswer = '{"documentType": "Policy"}';
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'cGMP.pdf');
            insert p;

            DocPdfRecommendationBuilder.build(p.Id, POLICY, 3, 3, true, null);
            Doc_PDF_Field__c owner = rowsOf(p.Id).get('OwnerId');
            Assert.areEqual(UserInfo.getUserId(), Id.valueOf(owner.Proposed_Value__c), owner.Evidence__c);
            Assert.areEqual(DocPdfRecommendationBuilder.AI_SOURCE, owner.Source__c);
        }
    }

    @IsTest
    static void noAiFieldsMeansNoAiCall() {
        System.runAs(appUser()) {
            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
                cfg('compliancequest__Title__c', 'Labeled_Value', 'Title', '{First Line}', null, null),
                cfg('OwnerId', 'Lookup_Match', null, null, '(?i)\\bnothing matches this\\b => Nobody', null)
            };
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'cGMP.pdf');
            insert p;
            DocPdfRecommendationBuilder.build(p.Id, POLICY, 3, 3, true, null);
            String status = [SELECT AI_Status__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id].AI_Status__c;
            Assert.isTrue(status.contains('not used'), status);
            Assert.isNull(rowsOf(p.Id).get('OwnerId').Proposed_Value__c);
        }
    }

    // ------------------------------------------------------------------ parser and create helpers

    @IsTest
    static void readsPolicyLayouts() {
        Assert.areEqual('Current Good Manufacturing Practices (cGMP) Fundamentals', DocPdfFieldParser.firstLineOf(POLICY));
        Assert.areEqual('SOP for Mixing', DocPdfFieldParser.firstLineOf('Document Number: SOP-1\nPage 1 of 3\nPURPOSE\nSOP for Mixing\n'));
        Assert.isNull(DocPdfFieldParser.firstLineOf(''));

        String purpose = DocPdfFieldParser.sectionText(POLICY, 'Purpose');
        Assert.isTrue(purpose.startsWith('This document sets out'), purpose);
        Assert.isFalse(purpose.contains('committed'), 'Stops at the next all-capitals heading: ' + purpose);
        Assert.isNotNull(DocPdfFieldParser.sectionText('Intro\nPurpose of this Procedure:\nTo explain mixing.\n', 'Purpose'));

        Assert.isTrue(DocPdfFieldParser.isCapsHeading('PRINCIPLES OF THIS POLICY'));
        Assert.isFalse(DocPdfFieldParser.isCapsHeading('Principles of this policy'));
        Assert.isFalse(DocPdfFieldParser.isCapsHeading('SOP-44123 [002]'));
    }

    @IsTest
    static void retryStartsFromACleanRecord() {
        Map<String, Object> values = new Map<String, Object>{
            'Id' => 'a1I000000000001AAA',
            'compliancequest__Title__c' => 'cGMP Fundamentals'
        };
        compliancequest__SQX_Controlled_Document__c d = DocPdfCreateDocumentAction.freshCopy(values);
        Assert.isNull(d.Id);
        Assert.areEqual('cGMP Fundamentals', d.compliancequest__Title__c);
    }
}
