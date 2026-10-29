/**
 * Tests for the record side of the agent: upload, select, build recommendations,
 * review and create. The parser and Google Vision are covered by DocPdfExtractionTest.
 */
@IsTest
private class DocPdfAgentTest {

    // Shortened text of the sample SOP, as a PDF reader returns it (watermark letters included).
    private static final String SAMPLE =
        'Document Number: SOP-44123\nRevision: 002\nTitle: Usage of Additives in Mixing Equipment\n' +
        'Department: Quality Assurance\n\nEffective Date: 13-Nov-2024\n\n' +
        'SOP for Usage of Additives in Mixing Equipment\nTable of Contents\n' +
        '1. Purpose.................................................3\n' +
        'Key Updates..............................................3\n' +
        'Copyright ComplianceQuest Inc. All rights reserved.\n' +
        'Document Number: SOP-44123\nRevision: 002\n' +
        '1. Purpose\nThe purpose of this SOP is to ensure the correct and consistent use of additives in concrete\n' +
        'mixing equipment to prevent issues such as mix instability. This procedure outlines the steps.\n' +
        't\nn\n2. Scope\nThis SOP applies to all personnel.\nu\nKey Updates\nC\n' +
        '1. Additive Compatibility and Selection\no\nEnsure compatibility testing of all additives before use, considering cement\n' +
        'o\nNew Guidance: Avoid using multiple additives unless compatibility has been\n' +
        '2. Additive Measurement and Dosage Controls\no\nNew Requirement: All batching equipment must have automated dosage\n' +
        'Environmental Considerations for Additives\no\nExpanded Section: Adjust additive dosages.\n' +
        '3. Responsibilities\nOperator: Responsible for measuring.\n' +
        'Author:\nJoanne StAndre\nDocument Category: Procedure\nDocument Status:\nCurrent\n' +
        'Date Approved:\n14-Oct-2024\nExpiration Date:\n\nApproval History\nStep\nName of Approver\n' +
        'Revision History\nRevision Number\nChanges\n001\nN/A\n14-Oct-2024\nu\n' +
        'Related Documents\nC\nDocument Number\nTitle\nAPROC-9648[004]\nCleaning Procedure\n' +
        'Requirements\ne\nrr\nEffective Date\nJob Function\nDescription\nQuality Assurance\n' +
        'All Quality Assurance personnel\nQuality Control\nAll Quality Control Personnel\n' +
        'Copyright ComplianceQuest Inc. All rights reserved.';

    private static ContentVersion makePdf() {
        ContentVersion cv = new ContentVersion(
            Title = 'Usage of Additives in Mixing Equipment',
            PathOnClient = 'Usage_of_Additives_in_Mixing_Equipment.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test')
        );
        insert cv;
        return [SELECT Id, ContentDocumentId, FileType FROM ContentVersion WHERE Id = :cv.Id];
    }


    /** The four fields of the shipped Doc PDF Field Config, so tests do not depend on the org's setup. */
    private static void useTestConfig() {
        DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
            cfg('compliancequest__Title__c', 'Document Title', true, true, 'Labeled_Value', 'Title', null, null),
            cfg('compliancequest__Description__c', null, false, true, 'Section_First_Sentence', 'Purpose', null, null),
            cfg('compliancequest__Document_Category__c', null, false, true, 'Picklist_Match', 'Document Category', null,
                '(?im)^document number:\\s*SOP => SOP'),
            cfg('RecordTypeId', 'Record Type', false, false, 'Fixed_Value', null, 'Controlled_Document', null)
        };
    }

    private static DocPdfRecommendationBuilder.FieldConfig cfg(String api, String label, Boolean required, Boolean editable,
                                                               String source, String pdfLabel, String defaultValue, String rules) {
        DocPdfRecommendationBuilder.FieldConfig c = new DocPdfRecommendationBuilder.FieldConfig();
        c.apiName = api;
        c.label = label;
        c.required = required;
        c.editable = editable;
        c.source = source;
        c.pdfLabel = pdfLabel;
        c.defaultValue = defaultValue;
        c.matchRules = rules;
        return c;
    }

    /** The running user with the agent permission set, so USER_MODE queries and DML see the new fields. */
    private static User agentUser() {
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
    // ------------------------------------------------------------------ end to end

    @IsTest
    static void uploadSelectBuildReviewCreate() {
        System.runAs(agentUser()) {
            useTestConfig();
            ContentVersion cv = makePdf();

            DocPdfUploadController.StartData start = DocPdfUploadController.start();
            Assert.isTrue(start.success, '' + start.errorMessage);
            Assert.isNotNull(start.proposalId);
            Assert.isFalse(start.recentFiles.isEmpty());

            DocPdfFileSelection sel = new DocPdfFileSelection();
            sel.proposalId = start.proposalId;
            sel.contentDocumentId = cv.ContentDocumentId;
            DocPdfSelectFileAction.Request sreq = new DocPdfSelectFileAction.Request();
            sreq.selection = sel;
            DocPdfSelectFileAction.Result picked = DocPdfSelectFileAction.run(new List<DocPdfSelectFileAction.Request>{ sreq })[0];
            Assert.isTrue(picked.success, '' + picked.message);
            Assert.areEqual(start.proposalId, picked.proposalId);

            DocPdfBuildRecommendationsAction.Request breq = new DocPdfBuildRecommendationsAction.Request();
            breq.proposalId = picked.proposalId;
            breq.extractedText = SAMPLE;
            breq.pagesRead = 11;
            breq.totalPages = 11;
            breq.extractionSucceeded = true;
            DocPdfBuildRecommendationsAction.Result built =
                DocPdfBuildRecommendationsAction.run(new List<DocPdfBuildRecommendationsAction.Request>{ breq })[0];
            Assert.isTrue(built.success, '' + built.summary);
            Assert.isTrue(built.readyCount > 0);

            DocPdfReviewController.ReviewData data = DocPdfReviewController.getReview(null);
            Assert.isTrue(data.success, '' + data.errorMessage);
            Assert.areEqual(picked.proposalId, data.proposalId);
            Assert.isFalse(data.rows.isEmpty());

            // First submit with nothing decided: blocked, nothing created.
            DocPdfReview blocked = new DocPdfReview();
            blocked.proposalId = data.proposalId;
            DocPdfCreateDocumentAction.Result r1 = submit(blocked);
            Assert.isFalse(r1.success);
            Assert.isTrue(r1.undecidedCount > 0, '' + r1.summary);

            // Accept everything that has a value, clear the rest.
            List<Map<String, Object>> decisions = new List<Map<String, Object>>();
            for (DocPdfReviewController.RowDto row : data.rows) {
                if (row.decision == 'locked') {
                    continue;
                }
                decisions.add(new Map<String, Object>{
                    'id' => row.id,
                    'decision' => String.isBlank(row.proposedValue) ? 'clear' : 'accept'
                });
            }
            DocPdfReview review = new DocPdfReview();
            review.proposalId = data.proposalId;
            review.decisionsJson = JSON.serialize(decisions);
            review.readyToCreate = true;
            Test.startTest();
            DocPdfCreateDocumentAction.Result r2 = submit(review);
            Test.stopTest();
            Assert.areEqual(0, r2.undecidedCount, '' + r2.summary);
            Assert.isNotNull(r2.summary);
            if (r2.success) {
                Doc_PDF_Proposal__c p = [SELECT Status__c, Created_Record_Id__c FROM Doc_PDF_Proposal__c WHERE Id = :data.proposalId];
                Assert.areEqual('Created', p.Status__c);
                Assert.areEqual(r2.recordId, p.Created_Record_Id__c);
            }
        }
    }

    @IsTest
    static void failedExtractionMarksProposalFailed() {
        System.runAs(agentUser()) {
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft');
            insert p;
            DocPdfBuildRecommendationsAction.Request breq = new DocPdfBuildRecommendationsAction.Request();
            breq.proposalId = p.Id;
            breq.extractionSucceeded = false;
            breq.extractionMessage = 'Google Vision rejected the request (403).';
            DocPdfBuildRecommendationsAction.Result r =
                DocPdfBuildRecommendationsAction.run(new List<DocPdfBuildRecommendationsAction.Request>{ breq })[0];
            Assert.isFalse(r.success);
            Assert.areEqual('Failed', [SELECT Status__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id].Status__c);
        }
    }

    @IsTest
    static void selectRejectsNonPdf() {
        System.runAs(agentUser()) {
            ContentVersion txt = new ContentVersion(Title = 'notes', PathOnClient = 'notes.txt', VersionData = Blob.valueOf('x'));
            insert txt;
            DocPdfFileSelection sel = new DocPdfFileSelection();
            sel.contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :txt.Id].ContentDocumentId;
            Assert.isFalse(DocPdfSelectFileAction.runOne(sel).success);
            Assert.isFalse(DocPdfSelectFileAction.runOne(null).success);
        }
    }

    @IsTest
    static void decisionRules() {
        System.runAs(agentUser()) {
            Doc_PDF_Field__c accept = new Doc_PDF_Field__c(Decision__c = 'accept', Proposed_Value__c = 'A', Required__c = true);
            Doc_PDF_Field__c edit = new Doc_PDF_Field__c(Decision__c = 'undecided', Proposed_Value__c = 'B');
            Doc_PDF_Field__c locked = new Doc_PDF_Field__c(Decision__c = 'locked', Proposed_Value__c = 'C');
            DocPdfCreateDocumentAction.applyDecisions(new List<Doc_PDF_Field__c>{ accept, edit, locked }, null);
            Assert.areEqual('A', accept.Final_Value__c);
            Assert.isFalse(DocPdfCreateDocumentAction.isBlocked(accept));
            Assert.isTrue(DocPdfCreateDocumentAction.isBlocked(edit));
            Assert.isFalse(DocPdfCreateDocumentAction.isBlocked(locked));
            Doc_PDF_Field__c requiredBlank = new Doc_PDF_Field__c(Decision__c = 'clear', Required__c = true);
            Assert.isTrue(DocPdfCreateDocumentAction.isBlocked(requiredBlank));

            Schema.DescribeFieldResult dateField =
                compliancequest__SQX_Controlled_Document__c.compliancequest__Effective_Date__c.getDescribe();
            Assert.areEqual(Date.newInstance(2024, 11, 13), DocPdfCreateDocumentAction.coerce(dateField, '2024-11-13'));
            Assert.areEqual('accept', DocPdfRecommendationBuilder.defaultDecision('ready', 'x'));
            Assert.areEqual('clear', DocPdfRecommendationBuilder.defaultDecision('optional', null));
            Assert.areEqual('2 KB', DocPdfUploadController.sizeLabel(2048));
        }
    }

    // ------------------------------------------------------------------ component saves the choice

    @IsTest
    static void componentSavesChoiceAndAnalyzeFindsIt() {
        System.runAs(agentUser()) {
            ContentVersion cv = makePdf();
            DocPdfUploadController.StartData start = DocPdfUploadController.start();
            Assert.isTrue(start.success, '' + start.errorMessage);

            DocPdfUploadController.SelectResult saved =
                DocPdfUploadController.selectFile(start.proposalId, cv.ContentDocumentId);
            Assert.isTrue(saved.success, '' + saved.errorMessage);
            Assert.areEqual(start.proposalId, saved.proposalId);

            // Analyze with no Proposal Id finds the saved choice.
            DocPdfResolveProposalAction.Result found = DocPdfResolveProposalAction.run(
                new List<DocPdfResolveProposalAction.Request>{ new DocPdfResolveProposalAction.Request() })[0];
            Assert.isTrue(found.found, '' + found.message);
            Assert.areEqual(saved.proposalId, found.proposalId);
            Assert.areEqual((String) cv.Id, found.contentVersionId);

            // With the Proposal Id given.
            Assert.areEqual(saved.proposalId, DocPdfResolveProposalAction.resolve(saved.proposalId).proposalId);

            // Select PDF submitted without a value falls back to the saved choice.
            DocPdfSelectFileAction.Result fallback = DocPdfSelectFileAction.runOne(new DocPdfFileSelection());
            Assert.isTrue(fallback.success, '' + fallback.message);
            Assert.areEqual(saved.proposalId, fallback.proposalId);

            Assert.isFalse(DocPdfUploadController.selectFile(start.proposalId, '').success);
        }
    }

    @IsTest
    static void nothingChosenGivesClearMessage() {
        System.runAs(agentUser()) {
            DocPdfResolveProposalAction.Result r = DocPdfResolveProposalAction.resolve(null);
            Assert.isFalse(r.found);
            Assert.isNotNull(r.message);
            Assert.isFalse(DocPdfResolveProposalAction.resolve('not-an-id').found);

            DocPdfBuildRecommendationsAction.Request breq = new DocPdfBuildRecommendationsAction.Request();
            DocPdfBuildRecommendationsAction.Result built =
                DocPdfBuildRecommendationsAction.run(new List<DocPdfBuildRecommendationsAction.Request>{ breq })[0];
            Assert.isFalse(built.success);
            Assert.isTrue(built.summary.contains('No PDF'), '' + built.summary);
        }
    }

    @IsTest
    static void componentSavesDecisionsAndCreateUsesThem() {
        System.runAs(agentUser()) {
            useTestConfig();
            ContentVersion cv = makePdf();
            DocPdfFileSelection sel = new DocPdfFileSelection();
            sel.contentDocumentId = cv.ContentDocumentId;
            DocPdfSelectFileAction.Result picked = DocPdfSelectFileAction.runOne(sel);
            Assert.isTrue(picked.success, '' + picked.message);

            DocPdfBuildRecommendationsAction.Request breq = new DocPdfBuildRecommendationsAction.Request();
            breq.proposalId = picked.proposalId;
            breq.extractedText = SAMPLE;
            breq.pagesRead = 11;
            breq.totalPages = 11;
            breq.extractionSucceeded = true;
            Assert.isTrue(DocPdfBuildRecommendationsAction.run(
                new List<DocPdfBuildRecommendationsAction.Request>{ breq })[0].success);

            DocPdfReviewController.ReviewData data = DocPdfReviewController.getReview(picked.proposalId);
            List<Map<String, Object>> decisions = new List<Map<String, Object>>();
            for (DocPdfReviewController.RowDto row : data.rows) {
                if (row.decision != 'locked') {
                    decisions.add(new Map<String, Object>{
                        'id' => row.id,
                        'decision' => String.isBlank(row.proposedValue) ? 'clear' : 'accept'
                    });
                }
            }
            DocPdfReviewController.SaveResult saved =
                DocPdfReviewController.saveDecisions(data.proposalId, JSON.serialize(decisions));
            Assert.isTrue(saved.success, '' + saved.errorMessage);

            // The agent submits without passing the component's value: the saved decisions are used.
            Test.startTest();
            DocPdfCreateDocumentAction.Result r = submit(null);
            Test.stopTest();
            Assert.areEqual(0, r.undecidedCount, '' + r.summary);
            Assert.isNotNull(r.summary);
        }
    }

    @IsTest
    static void configDrivesTheReviewRows() {
        System.runAs(agentUser()) {
            useTestConfig();
            DocPdfRecommendationBuilder.testConfig.add(
                cfg('compliancequest__Effective_Date__c', null, false, true, 'Labeled_Value', 'Effective Date', null, null));
            DocPdfRecommendationBuilder.testConfig.add(
                cfg('compliancequest__No_Such_Field__c', null, false, true, 'Labeled_Value', 'Title', null, null));
            DocPdfRecommendationBuilder.testConfig.add(
                cfg('OwnerId', null, false, true, 'Lookup_Match', 'Author', null, null));
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'Sample.pdf');
            insert p;

            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(p.Id, SAMPLE, 11, 11, true, null);
            Assert.isTrue(s.success, '' + s.message);
            Assert.isTrue(s.message.contains('compliancequest__No_Such_Field__c'), '' + s.message);

            Map<String, Doc_PDF_Field__c> byApi = new Map<String, Doc_PDF_Field__c>();
            for (Doc_PDF_Field__c f : [
                SELECT Field_API_Name__c, Section__c, Decision__c, Proposed_Value__c, Proposed_Display__c, Source__c
                FROM Doc_PDF_Field__c WHERE Proposal__c = :p.Id
            ]) {
                byApi.put(f.Field_API_Name__c, f);
            }
            Doc_PDF_Field__c title = byApi.get('compliancequest__Title__c');
            Assert.areEqual('ready', title.Section__c);
            Assert.areEqual('Usage of Additives in Mixing Equipment', title.Proposed_Value__c);

            Doc_PDF_Field__c descr = byApi.get('compliancequest__Description__c');
            Assert.areEqual('review', descr.Section__c);
            Assert.isTrue(descr.Proposed_Value__c.startsWith('The purpose of this SOP'), '' + descr.Proposed_Value__c);

            Doc_PDF_Field__c cat = byApi.get('compliancequest__Document_Category__c');
            Assert.isNotNull(cat);

            Doc_PDF_Field__c rt = byApi.get('RecordTypeId');
            Assert.areEqual('locked', rt.Decision__c);
            Schema.RecordTypeInfo info = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName().get('Controlled_Document');
            if (info != null && info.isAvailable()) {
                Assert.areEqual((String) info.getRecordTypeId(), rt.Proposed_Value__c);
            }

            if (byApi.containsKey('compliancequest__Effective_Date__c')) {
                Assert.areEqual('2024-11-13', byApi.get('compliancequest__Effective_Date__c').Proposed_Value__c);
            }
            Assert.isFalse(byApi.containsKey('compliancequest__No_Such_Field__c'));
            Assert.areEqual('locked', byApi.get(DocPdfRecommendationBuilder.PRIMARY_CONTENT_KEY).Decision__c);

            // A locked fixed value is written; an information row is not.
            List<Doc_PDF_Field__c> rows = new List<Doc_PDF_Field__c>{
                rt, byApi.get(DocPdfRecommendationBuilder.PRIMARY_CONTENT_KEY) };
            for (Doc_PDF_Field__c f : rows) {
                f.Field_Type__c = f.Field_API_Name__c == 'RecordTypeId' ? 'reference' : 'info';
            }
            DocPdfCreateDocumentAction.applyDecisions(rows, null);
            Assert.areEqual(rt.Proposed_Value__c, rows[0].Final_Value__c);
            Assert.isNull(rows[1].Final_Value__c);
        }
    }

    @IsTest
    static void matchRulesAndDefaults() {
        System.runAs(agentUser()) {
            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>{
                cfg('compliancequest__Document_Category__c', null, false, true, 'Picklist_Match', 'No Such Label', null,
                    'not valid [regex => X\n(?im)^document number:\\s*SOP => SOP'),
                cfg('compliancequest__Description__c', null, false, true, 'Section_Text', 'No Such Section', 'Default text', null),
                cfg('compliancequest__Title__c', null, true, true, 'User_Input', null, null, null)
            };
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft');
            insert p;
            DocPdfRecommendationBuilder.Summary s = DocPdfRecommendationBuilder.build(p.Id, SAMPLE, 1, 1, true, null);
            Assert.isTrue(s.success, '' + s.message);
            Map<String, Doc_PDF_Field__c> byApi = new Map<String, Doc_PDF_Field__c>();
            for (Doc_PDF_Field__c f : [
                SELECT Field_API_Name__c, Section__c, Proposed_Value__c, Source__c
                FROM Doc_PDF_Field__c WHERE Proposal__c = :p.Id
            ]) {
                byApi.put(f.Field_API_Name__c, f);
            }
            Doc_PDF_Field__c cat = byApi.get('compliancequest__Document_Category__c');
            Schema.DescribeFieldResult catField =
                compliancequest__SQX_Controlled_Document__c.compliancequest__Document_Category__c.getDescribe();
            Boolean hasSop = false;
            for (Schema.PicklistEntry e : catField.getPicklistValues()) {
                hasSop = hasSop || (e.isActive() && e.getValue() == 'SOP');
            }
            if (hasSop) {
                Assert.areEqual('SOP', cat.Proposed_Value__c);
                // By rule, or by the best-fit template when the org's Category Templates list SOP headings.
                Assert.isTrue(cat.Source__c == 'By rule' || cat.Source__c == DocPdfRecommendationBuilder.BEST_FIT_SOURCE, cat.Source__c);
            }
            Assert.areEqual('Default text', byApi.get('compliancequest__Description__c').Proposed_Value__c);
            Assert.areEqual('Default', byApi.get('compliancequest__Description__c').Source__c);
            Assert.areEqual('input', byApi.get('compliancequest__Title__c').Section__c);

            DocPdfRecommendationBuilder.testConfig = new List<DocPdfRecommendationBuilder.FieldConfig>();
            Doc_PDF_Proposal__c p2 = new Doc_PDF_Proposal__c(Status__c = 'Draft');
            insert p2;
            Assert.isFalse(DocPdfRecommendationBuilder.build(p2.Id, SAMPLE, 1, 1, true, null).success);
        }
    }

    @IsTest
    static void parserGenericLookups() {
        Assert.areEqual('Usage of Additives in Mixing Equipment', DocPdfFieldParser.labeledValue(SAMPLE, 'Title:'));
        Assert.areEqual('Joanne StAndre', DocPdfFieldParser.labeledValue(SAMPLE, 'Author'));
        String purpose = DocPdfFieldParser.sectionText(SAMPLE, 'Purpose');
        Assert.isTrue(purpose.startsWith('The purpose of this SOP'), '' + purpose);
        Assert.isFalse(purpose.contains('This SOP applies to all personnel'), '' + purpose);
        Assert.isNull(DocPdfFieldParser.sectionText(SAMPLE, 'Nothing Here'));
        Assert.areEqual('2024-11-13', DocPdfFieldParser.isoDate('13-Nov-2024'));
        Assert.areEqual('One.', DocPdfFieldParser.firstSentenceOf('One. Two.', 100));
    }

    @IsTest
    static void createStepHelpers() {
        System.runAs(agentUser()) {
            // Values converted to each field type.
            Assert.areEqual(Datetime.newInstance(2024, 11, 13, 8, 30, 0),
                DocPdfCreateDocumentAction.coerce(Doc_PDF_Proposal__c.CreatedDate.getDescribe(), '2024-11-13T08:30:00'));
            Assert.areEqual(true, DocPdfCreateDocumentAction.coerce(Doc_PDF_Field__c.Required__c.getDescribe(), 'TRUE'));
            Assert.areEqual(Decimal.valueOf('12'), DocPdfCreateDocumentAction.coerce(Doc_PDF_Proposal__c.Pages_Read__c.getDescribe(), '12'));
            Assert.areEqual(UserInfo.getUserId(), DocPdfCreateDocumentAction.coerce(Doc_PDF_Proposal__c.OwnerId.getDescribe(), UserInfo.getUserId()));
            Assert.areEqual('0123456789', ((String) DocPdfCreateDocumentAction.coerce(
                Doc_PDF_Proposal__c.Content_Version_Id__c.getDescribe(), '0123456789012345678901')).left(10));

            Assert.isTrue(DocPdfCreateDocumentAction.isRecordField(new Doc_PDF_Field__c(Field_API_Name__c = 'compliancequest__Title__c', Field_Type__c = 'string')));
            Assert.isFalse(DocPdfCreateDocumentAction.isRecordField(new Doc_PDF_Field__c(Field_API_Name__c = 'info:primaryContent', Field_Type__c = 'info')));
            Assert.isFalse(DocPdfCreateDocumentAction.isRecordField(new Doc_PDF_Field__c(Field_API_Name__c = 'related:document')));

            List<String> notes = new List<String>();
            Assert.areEqual(0, DocPdfCreateDocumentAction.saveChildren(new List<SObject>(), new List<Doc_PDF_Field__c>(), notes));
            // A child that cannot be saved (no parent) is reported, not thrown.
            Doc_PDF_Field__c orphan = new Doc_PDF_Field__c(Field_Label__c = 'Training Requirement', Final_Display__c = 'Quality');
            Assert.areEqual(0, DocPdfCreateDocumentAction.saveChildren(
                new List<SObject>{ new Doc_PDF_Field__c(Field_API_Name__c = 'x') }, new List<Doc_PDF_Field__c>{ orphan }, notes));
            Assert.isTrue(orphan.Outcome__c.startsWith('Failed'), orphan.Outcome__c);
            Assert.isFalse(notes.isEmpty());

            // Linking the PDF, and setting it as Primary Content.
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft');
            insert p;
            ContentVersion cv = makePdf();
            Assert.isFalse(DocPdfCreateDocumentAction.linkFile(null, p.Id, notes));
            Assert.isTrue(DocPdfCreateDocumentAction.linkFile(cv.ContentDocumentId, p.Id, notes));
            Map<String, Schema.SObjectField> cdFields =
                compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().fields.getMap();
            Assert.isFalse(DocPdfCreateDocumentAction.setPrimaryContent(null, p.Id, cdFields, notes));
            // Not a Controlled Document Id: the update fails and is reported as a note.
            Assert.isFalse(DocPdfCreateDocumentAction.setPrimaryContent(cv.ContentDocumentId, p.Id, cdFields, notes));
        }
    }

    @IsTest
    static void createStepEdgeCases() {
        System.runAs(agentUser()) {
            // No proposal waiting.
            DocPdfCreateDocumentAction.Result none = submit(null);
            Assert.isFalse(none.success);
            Assert.isTrue(none.summary.contains('no PDF waiting'), none.summary);

            // Already created: returns the existing record.
            Doc_PDF_Proposal__c done = new Doc_PDF_Proposal__c(Status__c = 'Created',
                Created_Record_Id__c = UserInfo.getUserId(), Created_Record_Name__c = 'SOP-1[001]');
            insert done;
            DocPdfReview again = new DocPdfReview();
            again.proposalId = done.Id;
            DocPdfCreateDocumentAction.Result r = submit(again);
            Assert.isTrue(r.success, r.summary);
            Assert.areEqual('SOP-1[001]', r.documentName);

            // Edited values and a decision for a saved row.
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review');
            insert p;
            Doc_PDF_Field__c row = new Doc_PDF_Field__c(Proposal__c = p.Id, Field_API_Name__c = 'compliancequest__Title__c',
                Field_Label__c = 'Title', Field_Type__c = 'string', Decision__c = 'undecided', Proposed_Value__c = 'Old', Sort_Order__c = 10);
            insert row;
            List<Doc_PDF_Field__c> rows = [SELECT Id, Decision__c, Proposed_Value__c, Proposed_Display__c, Final_Value__c,
                Final_Display__c, Field_Type__c, Field_API_Name__c, Required__c FROM Doc_PDF_Field__c WHERE Id = :row.Id];
            DocPdfCreateDocumentAction.applyDecisions(rows, JSON.serialize(new List<Map<String, Object>>{
                new Map<String, Object>{ 'id' => row.Id, 'decision' => 'edit', 'value' => 'New title', 'display' => null } }));
            Assert.areEqual('edit', rows[0].Decision__c);
            Assert.areEqual('New title', rows[0].Final_Value__c);
            Assert.areEqual('New title', rows[0].Final_Display__c);
        }
    }

    private static DocPdfCreateDocumentAction.Result submit(DocPdfReview review) {
        DocPdfCreateDocumentAction.Request req = new DocPdfCreateDocumentAction.Request();
        req.review = review;
        return DocPdfCreateDocumentAction.run(new List<DocPdfCreateDocumentAction.Request>{ req })[0];
    }
}
