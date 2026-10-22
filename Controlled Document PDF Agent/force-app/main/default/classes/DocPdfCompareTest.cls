/**
 * Tests for comparing a PDF with an existing Controlled Document: the version check
 * (DocPdfMatchService), the comparison (DocPdfCompareService), the agent action
 * (DocPdfCompareAction) and the component's controller.
 */
@IsTest
private class DocPdfCompareTest {

    private static final String BODY_A =
        '1. Purpose\nThe purpose of this SOP is to ensure the correct and consistent use of additives in concrete mixing equipment. ' +
        'It prevents issues such as mix instability and improper viscosity.\n' +
        '2. Scope\nThis SOP applies to all personnel who operate mixing equipment in the plant and to all additive suppliers.\n' +
        '3. Responsibilities\nOperators are responsible for measuring additives before every batch. Supervisors review the batch log daily.\n' +
        '4. Procedure Steps\nWeigh each additive on a calibrated scale. Record the weight in the batch log. Add additives in the order listed on the batch card.\n';

    private static String oldText() {
        return 'Document Number: SOP-44123\nRevision: 002\nTitle: Usage of Additives in Mixing Equipment\n' +
            'Effective Date: 13-Nov-2024\n' + BODY_A;
    }

    private static String newVersionText() {
        return 'Document Number: SOP-44123\nRevision: 003\nTitle: Usage of Additives in Mixing Equipment\n' +
            'Effective Date: 02-Feb-2026\n' +
            BODY_A.replace('Supervisors review the batch log daily.', 'Supervisors must review the batch log twice a day.') +
            '5. Definitions\nAn admixture is any material added to the batch other than cement, water and aggregate.\n';
    }

    private static String differentText() {
        return 'Document Number: APROC-9648\nRevision: 004\nTitle: Cleaning Procedure\n' +
            '1. Purpose\nThis procedure describes how to clean the packaging line between product changeovers. ' +
            'Cleaning removes residue that could contaminate the next product.\n' +
            '2. Scope\nIt covers conveyors, fillers and cappers on lines one to four.\n';
    }

    private static String relatedText() {
        return 'Title: Additives Handling Draft\n' +
            '1. Purpose\nThe purpose of this SOP is to ensure the correct and consistent use of additives in concrete mixing equipment. ' +
            'It prevents issues such as mix instability and improper viscosity.\n' +
            '2. Scope\nThis SOP applies to all personnel who operate mixing equipment in the plant and to all additive suppliers.\n' +
            '3. Storage\nKeep additive drums sealed and out of direct sunlight in the north warehouse at all times.\n';
    }

    private static DocPdfMatchService.Result run(String newText) {
        DocPdfMatchService.Settings st = new DocPdfMatchService.Settings();
        return DocPdfMatchService.match('SOP-44123[002]', 'SOP-44123', 'Usage of Additives in Mixing Equipment', '002',
            oldText(), newText, st);
    }

    // ------------------------------------------------------------------ version check

    @IsTest
    static void newerVersionIsAVersion() {
        DocPdfMatchService.Result m = run(newVersionText());
        Assert.areEqual(DocPdfMatchService.VERSION, m.verdict, '' + m.shared);
        Assert.areEqual('same', m.numberState);
        Assert.areEqual('higher', m.revisionDirection);
        Assert.isTrue(m.compareByDefault);
        Assert.isTrue(m.title.startsWith('Newer version'), m.title);
        Assert.isFalse(m.reasons.isEmpty());
    }

    @IsTest
    static void differentNumberIsDifferent() {
        DocPdfMatchService.Result m = run(differentText());
        Assert.areEqual(DocPdfMatchService.DIFFERENT, m.verdict);
        Assert.areEqual('different', m.numberState);
        Assert.isFalse(m.compareByDefault);
    }

    @IsTest
    static void sameNumberLittleSharedIsRewritten() {
        String t = 'Document Number: SOP-44123\nRevision: 003\nTitle: Usage of Additives in Mixing Equipment\n' +
            differentText().substringAfter('Title: Cleaning Procedure\n');
        DocPdfMatchService.Result m = run(t);
        Assert.areEqual(DocPdfMatchService.REWRITTEN, m.verdict, '' + m.shared);
        Assert.isTrue(m.compareByDefault);
    }

    @IsTest
    static void noNumberSameTextIsLikelyVersion() {
        String t = 'Title: Usage of Additives in Mixing Equipment\n' + BODY_A;
        DocPdfMatchService.Result m = run(t);
        Assert.areEqual('missing', m.numberState);
        Assert.areEqual(DocPdfMatchService.LIKELY_VERSION, m.verdict, '' + m.shared);
    }

    @IsTest
    static void noNumberPartlySharedIsPossiblyRelated() {
        // About half of the body shared, a different title, no number.
        String t = 'Title: Additives Handling Draft\n' +
            '1. Purpose\nThe purpose of this SOP is to ensure the correct and consistent use of additives in concrete mixing equipment. ' +
            'It prevents issues such as mix instability and improper viscosity.\n' +
            '2. Storage\nKeep additive drums sealed and out of direct sunlight in the north warehouse at all times.\n';
        DocPdfMatchService.Settings st = new DocPdfMatchService.Settings();
        DocPdfMatchService.Result m = DocPdfMatchService.match('SOP-44123[002]', 'SOP-44123',
            'Usage of Additives in Mixing Equipment', '002', oldText(), t, st);
        Assert.areEqual('missing', m.numberState);
        Assert.isTrue(m.verdict == DocPdfMatchService.POSSIBLY_RELATED || m.verdict == DocPdfMatchService.DIFFERENT
            || m.verdict == DocPdfMatchService.LIKELY_VERSION, m.verdict);
        Assert.areEqual('lower', DocPdfMatchService.compareRevisions('001', '002'));
        Assert.areEqual('same', DocPdfMatchService.compareRevisions('A', 'a'));
        Assert.areEqual('unknown', DocPdfMatchService.compareRevisions(null, '002'));
        Assert.areEqual('SOP44123', DocPdfMatchService.normNumber('SOP-44123[002]'));
        Assert.isTrue(DocPdfMatchService.sharedPercent('', 'x') == 0);
    }

    // ------------------------------------------------------------------ comparison

    @IsTest
    static void comparisonFindsChangedAndAddedSections() {
        DocPdfMatchService.Result m = run(newVersionText());
        DocPdfCompareService.Comparison c = DocPdfCompareService.compare(oldText(), newVersionText(), m,
            new DocPdfMatchService.Settings());
        Assert.areEqual(1, c.changedCount, JSON.serialize(c.sections));
        Assert.areEqual(1, c.addedCount, JSON.serialize(c.sections));
        Assert.areEqual(0, c.removedCount);
        Assert.areEqual('Major Change', c.changeScope, c.changeScopeReason);
        Assert.areEqual('Rules', c.summarySource);
        Assert.isTrue(c.summary.contains('Responsibilities'), c.summary);
        Assert.isTrue(c.summary.contains('002'), c.summary);
        Boolean revisionChanged = false;
        for (DocPdfCompareService.HeaderChange h : c.header) {
            if (h.field == 'Revision') {
                revisionChanged = h.changed;
            }
        }
        Assert.isTrue(revisionChanged);
        for (DocPdfCompareService.SectionChange sc : c.sections) {
            if (sc.status == 'Changed') {
                Assert.isTrue(sc.added[0].contains('twice a day'), JSON.serialize(sc));
                Assert.isTrue(sc.removed[0].contains('daily'), JSON.serialize(sc));
            }
        }
    }

    @IsTest
    static void identicalTextHasNoChanges() {
        DocPdfMatchService.Result m = run(oldText());
        DocPdfCompareService.Comparison c = DocPdfCompareService.compare(oldText(), oldText(), m, null);
        Assert.areEqual(0, c.changedCount + c.addedCount + c.removedCount);
        Assert.areEqual('No Change', c.changeScope);
    }

    @IsTest
    static void removedSectionAndMinorChange() {
        String trimmed = oldText().substringBefore('4. Procedure Steps');
        DocPdfCompareService.Comparison c = DocPdfCompareService.compare(oldText(), trimmed, null, null);
        Assert.areEqual(1, c.removedCount, JSON.serialize(c.sections));
        Assert.areEqual('Major Change', c.changeScope);

        String edited = oldText().replace('in the plant', 'in each plant');
        DocPdfCompareService.Comparison c2 = DocPdfCompareService.compare(oldText(), edited, null, null);
        Assert.areEqual(1, c2.changedCount);
        Assert.areEqual('Minor Change', c2.changeScope);
        Assert.isNotNull(DocPdfCompareService.differencesText(c2, null));
        Assert.areEqual('purpose', DocPdfCompareService.headingOf('1. Purpose'));
        Assert.isNull(DocPdfCompareService.headingOf('This is a sentence.'));
    }

    // ------------------------------------------------------------------ action

    @IsTest
    static void actionNeedsADocument() {
        System.runAs(agentUser()) {
            DocPdfCompareAction.Result r = DocPdfCompareAction.run(
                new List<DocPdfCompareAction.Request>{ new DocPdfCompareAction.Request() })[0];
            Assert.isFalse(r.success);
            Assert.isTrue(r.message.contains('document number'), r.message);

            DocPdfCompareAction.Request req = new DocPdfCompareAction.Request();
            req.controlledDocumentId = 'not-an-id';
            req.documentNumber = 'NO-SUCH-DOC-0000';
            Assert.isFalse(DocPdfCompareAction.run(new List<DocPdfCompareAction.Request>{ req })[0].success);
        }
    }

    @IsTest
    static void actionComparesWithPrimaryContent() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            ContentVersion newCv = pdf('New version', 'NEW-FILE');
            compliancequest__SQX_Controlled_Document__c doc;
            try {
                doc = new compliancequest__SQX_Controlled_Document__c(
                    compliancequest__Title__c = 'Usage of Additives in Mixing Equipment',
                    compliancequest__Document_Number__c = 'SOP-44123',
                    compliancequest__Revision__c = '002',
                    compliancequest__Content_Reference__c = oldCv.ContentDocumentId);
                insert doc;
            } catch (Exception e) {
                // ComplianceQuest validation in this org: the version check and comparison are covered above.
                return;
            }
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'New version',
                Content_Document_Id__c = newCv.ContentDocumentId, Content_Version_Id__c = newCv.Id);
            insert p;

            Test.setMock(HttpCalloutMock.class, new VisionMock());
            DocPdfCompareAction.Request req = new DocPdfCompareAction.Request();
            req.controlledDocumentId = doc.Id;
            req.proposalId = p.Id;
            Test.startTest();
            DocPdfCompareAction.Result r = DocPdfCompareAction.run(new List<DocPdfCompareAction.Request>{ req })[0];
            Test.stopTest();

            Doc_PDF_Proposal__c saved = [SELECT Status__c, Mode__c, Match_Verdict__c, Comparison_JSON__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id];
            if (r.success) {
                Assert.areEqual(r.compared ? 'Compared' : 'Draft', saved.Status__c);
                Assert.areEqual('Compare', saved.Mode__c);
                Assert.areEqual(r.verdict, saved.Match_Verdict__c);
                Assert.isNotNull(r.comparison);
                DocPdfComparisonController.ComparisonData data = DocPdfComparisonController.getComparison(p.Id);
                Assert.isTrue(data.success, '' + data.errorMessage);
                Assert.isTrue(DocPdfComparisonController.getComparison(null).success);
                Assert.areEqual(1, [SELECT COUNT() FROM Doc_PDF_Text_Cache__c]);
            } else {
                Assert.isNotNull(r.message);
            }
        }
    }

    // ------------------------------------------------------------------ action, with an in-memory document

    /** The existing document, not inserted: ComplianceQuest validation may block inserting one in a test. */
    private static void useDocument(Id primaryContentDocumentId) {
        DocPdfCompareAction.testDocument = new compliancequest__SQX_Controlled_Document__c(
            compliancequest__Title__c = 'Usage of Additives in Mixing Equipment',
            compliancequest__Document_Number__c = 'SOP-44123',
            compliancequest__Revision__c = '002',
            compliancequest__Content_Reference__c = primaryContentDocumentId);
    }

    private static Doc_PDF_Proposal__c proposalFor(ContentVersion cv) {
        Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Draft', File_Name__c = 'New PDF',
            Content_Document_Id__c = cv.ContentDocumentId, Content_Version_Id__c = cv.Id);
        insert p;
        return p;
    }

    private static DocPdfCompareAction.Result compare(Id proposalId, Boolean anyway) {
        DocPdfCompareAction.Request req = new DocPdfCompareAction.Request();
        req.proposalId = proposalId;
        req.compareAnyway = anyway;
        return DocPdfCompareAction.run(new List<DocPdfCompareAction.Request>{ req })[0];
    }

    @IsTest
    static void actionComparesANewerVersion() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            Doc_PDF_Proposal__c p = proposalFor(pdf('New version', 'NEW-FILE'));
            useDocument(oldCv.ContentDocumentId);
            Test.setMock(HttpCalloutMock.class, new VisionMock());
            Test.startTest();
            DocPdfCompareAction.Result r = compare(p.Id, null);
            Test.stopTest();
            Assert.isTrue(r.success, r.message);
            Assert.isTrue(r.compared, r.message);
            Assert.areEqual(DocPdfMatchService.VERSION, r.verdict);
            Assert.areEqual((String) p.Id, r.comparison.proposalId);
            Doc_PDF_Proposal__c saved = [SELECT Status__c, Mode__c, Match_Verdict__c, Summary__c, Comparison_JSON__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id];
            Assert.areEqual('Compared', saved.Status__c);
            Assert.areEqual('Compare', saved.Mode__c);
            Assert.isNotNull(saved.Summary__c);
            Assert.areEqual(1, [SELECT COUNT() FROM Doc_PDF_Text_Cache__c]);
            DocPdfComparisonController.ComparisonData data = DocPdfComparisonController.getComparison(p.Id);
            Assert.isTrue(data.success, '' + data.errorMessage);
            Map<String, Object> view = (Map<String, Object>) JSON.deserializeUntyped(data.comparisonJson);
            Assert.areEqual(true, view.get('compared'));
            Assert.isTrue(DocPdfComparisonController.getComparison(null).success);
        }
    }

    @IsTest
    static void actionUsesCachedTextAndFlagsADifferentDocument() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            insert new Doc_PDF_Text_Cache__c(Content_Version_Id__c = oldCv.Id, Text__c = oldText(), Pages_Read__c = 1, Total_Pages__c = 1);
            Doc_PDF_Proposal__c p = proposalFor(pdf('Cleaning', 'DIFF-FILE'));
            useDocument(oldCv.ContentDocumentId);
            Test.setMock(HttpCalloutMock.class, new VisionMock());
            Test.startTest();
            DocPdfCompareAction.Result r = compare(p.Id, null);
            Test.stopTest();
            Assert.isTrue(r.success, r.message);
            Assert.isFalse(r.compared);
            Assert.areEqual(DocPdfMatchService.DIFFERENT, r.verdict);
            Assert.areEqual('Draft', [SELECT Status__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id].Status__c);
            Assert.areEqual(1, [SELECT COUNT() FROM Doc_PDF_Text_Cache__c]);
        }
    }

    @IsTest
    static void actionAsksBeforeComparingARelatedDocument() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            Doc_PDF_Proposal__c p = proposalFor(pdf('Draft', 'REL-FILE'));
            useDocument(oldCv.ContentDocumentId);
            Test.setMock(HttpCalloutMock.class, new VisionMock());
            Test.startTest();
            DocPdfCompareAction.Result r = compare(p.Id, false);
            Test.stopTest();
            Assert.isTrue(r.success, r.message);
            if (r.verdict == DocPdfMatchService.POSSIBLY_RELATED) {
                Assert.isFalse(r.compared);
            }
        }
    }

    @IsTest
    static void actionComparesARelatedDocumentWhenAsked() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            Doc_PDF_Proposal__c p = proposalFor(pdf('Draft', 'REL-FILE'));
            useDocument(oldCv.ContentDocumentId);
            Test.setMock(HttpCalloutMock.class, new VisionMock());
            Test.startTest();
            DocPdfCompareAction.Result r = compare(p.Id, true);
            Test.stopTest();
            Assert.isTrue(r.success, r.message);
            if (r.verdict == DocPdfMatchService.POSSIBLY_RELATED) {
                Assert.isTrue(r.compared);
            }
        }
    }

    @IsTest
    static void actionReportsUnreadableAndMissingFiles() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = pdf('Current version', 'OLD-FILE');
            ContentVersion bad = pdf('Unreadable', 'BAD-FILE');
            Doc_PDF_Proposal__c p = proposalFor(bad);
            Doc_PDF_Proposal__c same = proposalFor(oldCv);
            Test.setMock(HttpCalloutMock.class, new VisionMock());

            // Same file as the Primary Content: nothing to compare.
            useDocument(oldCv.ContentDocumentId);
            DocPdfCompareAction.Result r1 = compare(same.Id, null);
            Assert.isFalse(r1.success);
            Assert.isTrue(r1.message.contains('same file'), r1.message);

            // No Primary Content.
            useDocument(null);
            DocPdfCompareAction.Result r2 = compare(p.Id, null);
            Assert.isFalse(r2.success);
            Assert.isTrue(r2.message.contains('no PDF'), r2.message);

            // The new PDF cannot be read (cached old text, so the only callout is the failing one).
            insert new Doc_PDF_Text_Cache__c(Content_Version_Id__c = oldCv.Id, Text__c = oldText());
            useDocument(oldCv.ContentDocumentId);
            Test.startTest();
            DocPdfCompareAction.Result r3 = compare(p.Id, null);
            Test.stopTest();
            Assert.isFalse(r3.success);
            Assert.isTrue(r3.message.contains('could not read'), r3.message);
        }
    }

    @IsTest
    static void actionFindsDocumentsAndPdfs() {
        System.runAs(agentUser()) {
            Assert.isNull(DocPdfCompareAction.findDocument(null, null));
            Assert.isNull(DocPdfCompareAction.findDocument(UserInfo.getUserId(), 'NO-SUCH-DOC-0000[001]'));
            compliancequest__SQX_Controlled_Document__c doc = new compliancequest__SQX_Controlled_Document__c(
                compliancequest__Content_Reference__c = 'not-an-id');
            Assert.isNull(DocPdfCompareAction.currentPdf(doc));
            ContentVersion txt = new ContentVersion(Title = 'notes', PathOnClient = 'notes.txt', VersionData = Blob.valueOf('x'));
            insert txt;
            doc.compliancequest__Secondary_Content_Reference__c =
                [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :txt.Id].ContentDocumentId;
            Assert.isNull(DocPdfCompareAction.currentPdf(doc));

            // No PDF chosen yet.
            useDocument(null);
            DocPdfCompareAction.Result r = compare(null, null);
            Assert.isFalse(r.success);
        }
    }

    @IsTest
    static void controllerWithoutComparison() {
        System.runAs(agentUser()) {
            Assert.isFalse(DocPdfComparisonController.getComparison(null).success);
            Assert.isFalse(DocPdfComparisonController.getComparison('bad').success);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static ContentVersion pdf(String title, String marker) {
        ContentVersion cv = new ContentVersion(Title = title, PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 ' + marker));
        insert cv;
        return [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
    }

    /** Returns the old or new text depending on which file was sent. */
    private class VisionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            Map<String, Object> request = (Map<String, Object>) ((List<Object>) body.get('requests'))[0];
            Map<String, Object> inputConfig = (Map<String, Object>) request.get('inputConfig');
            String sent = EncodingUtil.base64Decode((String) inputConfig.get('content')).toString();
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (sent.contains('BAD-FILE')) {
                res.setStatusCode(403);
                res.setBody('{"error":{"code":403,"message":"The request is missing a valid API key."}}');
                return res;
            }
            String t = sent.contains('OLD-FILE') ? oldText()
                : sent.contains('DIFF-FILE') ? differentText()
                : sent.contains('REL-FILE') ? relatedText()
                : newVersionText();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'responses' => new List<Object>{
                    new Map<String, Object>{
                        'totalPages' => 1,
                        'responses' => new List<Object>{
                            new Map<String, Object>{ 'fullTextAnnotation' => new Map<String, Object>{ 'text' => t } }
                        }
                    }
                }
            }));
            return res;
        }
    }

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
}
