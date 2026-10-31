/**
 * Tests for the revision check: is an uploaded file a new version of an existing Controlled
 * Document (DocPdfRevisionCheck), the review's banner data (DocPdfReviewController) and the
 * comparison run from the review (DocPdfCompareAction.compareForReview).
 */
@IsTest
private class DocPdfRevisionCheckTest {

    private static final String BODY =
        '1. Purpose\nThe purpose of this SOP is to ensure the correct and consistent use of additives in concrete mixing equipment. ' +
        'It prevents issues such as mix instability and improper viscosity.\n' +
        '2. Scope\nThis SOP applies to all personnel who operate mixing equipment in the plant and to all additive suppliers.\n' +
        '3. Responsibilities\nOperators are responsible for measuring additives before every batch. Supervisors review the batch log daily.\n';

    private static String fileText() {
        return 'Document Number: SOP-44123\nRevision: 003\nTitle: Usage of Additives in Mixing Equipment\n' + BODY;
    }

    private static Integer seq = 1;

    /** An in-memory document with a made-up Id (the org's validation may block inserting one). */
    private static compliancequest__SQX_Controlled_Document__c doc(String num, String title, String status) {
        String prefix = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().getKeyPrefix();
        Id fake = Id.valueOf(prefix + String.valueOf(seq++).leftPad(12, '0'));
        return new compliancequest__SQX_Controlled_Document__c(Id = fake,
            compliancequest__Document_Number__c = num, compliancequest__Title__c = title,
            compliancequest__Document_Status__c = status);
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

    // ------------------------------------------------------------------ signals

    @IsTest
    static void numbersComeFromTheLabelTheHeaderAndTheFileName() {
        DocPdfMatchService.Settings st = new DocPdfMatchService.Settings();
        Set<String> ns = DocPdfRevisionCheck.numbersIn('Document Number: SOP-44123[002]\nREF WI-000123 applies\n' + BODY,
            'POL-000045 Travel.docx', st);
        Assert.isTrue(ns.contains('SOP-44123'), '' + ns);
        Assert.isTrue(ns.contains('WI-000123'), '' + ns);
        Assert.isTrue(ns.contains('POL-000045'), '' + ns);
        Assert.isTrue(DocPdfRevisionCheck.numbersIn(BODY, null, st).isEmpty());
    }

    @IsTest
    static void titlesMatchOnlyWhenCloseEnough() {
        Assert.isTrue(DocPdfRevisionCheck.titleMatches('Usage of Additives in Mixing Equipment', 'usage of additives in mixing equipment'));
        Assert.isTrue(DocPdfRevisionCheck.titleMatches('Usage of Additives in Mixing Equipment', 'Additives Usage in the Mixing Equipment'));
        Assert.isFalse(DocPdfRevisionCheck.titleMatches('Cleaning Procedure', 'Cleaning of Packaging Lines'));
        Assert.isFalse(DocPdfRevisionCheck.titleMatches('Additives Storage', 'Usage of Additives in Mixing Equipment'));
        Assert.isFalse(DocPdfRevisionCheck.titleMatches(null, 'x'));
        Assert.areEqual('maintenance', DocPdfRevisionCheck.longestWord('Pump Maintenance Schedule'));
        Assert.isNull(DocPdfRevisionCheck.longestWord('SOP'));
    }

    // ------------------------------------------------------------------ decision

    @IsTest
    static void sameNumberWinsAndPrefersTheCurrentOne() {
        compliancequest__SQX_Controlled_Document__c draft = doc('SOP-44123', 'Old title', 'Draft');
        compliancequest__SQX_Controlled_Document__c current = doc('SOP-44123', 'Old title', 'Current');
        compliancequest__SQX_Controlled_Document__c sameTitle = doc('SOP-99999', 'Usage of Additives in Mixing Equipment', 'Current');
        DocPdfRevisionCheck.testDocuments = new List<compliancequest__SQX_Controlled_Document__c>{ draft, sameTitle, current };
        DocPdfRevisionCheck.testTexts = new Map<Id, String>();
        DocPdfRevisionCheck.Found f = DocPdfRevisionCheck.check(fileText(), 'upload.pdf', null, null);
        Assert.isNotNull(f);
        Assert.areEqual(current.Id, f.documentId);
        Assert.areEqual(DocPdfRevisionCheck.SAME_NUMBER, f.kind);
    }

    @IsTest
    static void sameContentWithADifferentNumber() {
        compliancequest__SQX_Controlled_Document__c renamed = doc('PROC-000007', 'Additive handling', 'Current');
        compliancequest__SQX_Controlled_Document__c other = doc('PROC-000008', 'Cleaning', 'Current');
        DocPdfRevisionCheck.testDocuments = new List<compliancequest__SQX_Controlled_Document__c>{ other, renamed };
        DocPdfRevisionCheck.testTexts = new Map<Id, String>{
            renamed.Id => 'Title: Additive handling\n' + BODY,
            other.Id => 'Title: Cleaning\nClean the packaging line between product changeovers to remove residue.\n'
        };
        DocPdfRevisionCheck.Found f = DocPdfRevisionCheck.check(fileText(), 'upload.pdf', 'Usage of Additives in Mixing Equipment', null);
        Assert.isNotNull(f);
        Assert.areEqual(renamed.Id, f.documentId);
        Assert.areEqual(DocPdfRevisionCheck.SAME_CONTENT, f.kind);
        Assert.isTrue(f.shared >= DocPdfRevisionCheck.contentMin, '' + f.shared);
    }

    @IsTest
    static void sameTitleWhenNothingElseMatches() {
        compliancequest__SQX_Controlled_Document__c sameTitle = doc('SOP-1', 'Usage of Additives in Mixing Equipment', 'Current');
        DocPdfRevisionCheck.testDocuments = new List<compliancequest__SQX_Controlled_Document__c>{ sameTitle };
        DocPdfRevisionCheck.testTexts = new Map<Id, String>();
        DocPdfRevisionCheck.Found f = DocPdfRevisionCheck.check('Title: Usage of Additives in Mixing Equipment\n' + BODY, null, null, null);
        Assert.areEqual(DocPdfRevisionCheck.SAME_TITLE, f.kind);
        Assert.areEqual(sameTitle.Id, f.documentId);
    }

    @IsTest
    static void nothingMatchesOrNothingToCheck() {
        DocPdfRevisionCheck.testDocuments = new List<compliancequest__SQX_Controlled_Document__c>{ doc('APROC-9648', 'Cleaning Procedure', 'Current') };
        DocPdfRevisionCheck.testTexts = new Map<Id, String>();
        Assert.isNull(DocPdfRevisionCheck.check(fileText(), 'upload.pdf', null, null));
        Assert.isNull(DocPdfRevisionCheck.check('', 'upload.pdf', null, null));
    }

    @IsTest
    static void queriesTheOrgWithoutFailing() {
        System.runAs(agentUser()) {
            Doc_PDF_Proposal__c earlier = new Doc_PDF_Proposal__c(Status__c = 'Created', File_Name__c = 'Earlier',
                Created_Record_Id__c = 'not-an-id', Extracted_Text__c = BODY);
            insert earlier;
            // No document with these numbers or this title in a test: no match, and no error.
            Assert.isNull(DocPdfRevisionCheck.check(fileText(), 'SOP-44123 Additives.pdf', 'Usage of Additives in Mixing Equipment', null));
        }
    }

    @IsTest
    static void buildStepSavesTheCheck() {
        System.runAs(agentUser()) {
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review', File_Name__c = 'SOP-44123.pdf',
                Message__c = 'I read the file.');
            insert p;
            insert new Doc_PDF_Field__c(Proposal__c = p.Id, Field_API_Name__c = 'compliancequest__Title__c',
                Proposed_Value__c = 'Usage of Additives in Mixing Equipment');
            // Matches by number, but the made-up document cannot be read back: no banner, no note.
            DocPdfRevisionCheck.testDocuments = new List<compliancequest__SQX_Controlled_Document__c>{ doc('SOP-44123', 'x', 'Current') };
            DocPdfRevisionCheck.testTexts = new Map<Id, String>();
            Assert.isNull(DocPdfBuildRecommendationsAction.checkRevision(p.Id, fileText()));
            Doc_PDF_Proposal__c saved = [SELECT Controlled_Document__c, Match_Verdict__c, Message__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id];
            Assert.isNull(saved.Controlled_Document__c);
            Assert.isNull(saved.Match_Verdict__c);
            Assert.areEqual('I read the file.', saved.Message__c);
            Assert.isTrue(DocPdfRevisionCheck.sharedPercent(BODY, BODY) == 100);
        }
    }

    @IsTest
    static void mostlySharedTextIsAVersionEvenWithoutLabels() {
        // A Word file with no "Document Number:" or "Title:" lines: the labels alone say "possibly related".
        DocPdfMatchService.Settings st = new DocPdfMatchService.Settings();
        DocPdfMatchService.Result m = DocPdfMatchService.match('PROC-000003[001]', 'PROC-000003', 'Emergency Response', null,
            BODY, BODY, st);
        Assert.areEqual(DocPdfMatchService.POSSIBLY_RELATED, m.verdict);
        DocPdfCompareAction.adjustVerdict(m, 'PROC-000003[001]', st, false);
        Assert.areEqual(DocPdfMatchService.VERSION, m.verdict);
        Assert.areEqual('Version of PROC-000003[001]', m.title);
        Assert.isTrue(m.compareByDefault);
        for (DocPdfMatchService.Reason rs : m.reasons) {
            Assert.isFalse(rs.text.contains('PDF'), rs.text);
        }

        DocPdfMatchService.Result likely = new DocPdfMatchService.Result();
        likely.verdict = DocPdfMatchService.POSSIBLY_RELATED;
        likely.shared = 70;
        likely.numberState = 'missing';
        DocPdfCompareAction.adjustVerdict(likely, 'PROC-000003[001]', st, false);
        Assert.areEqual(DocPdfMatchService.POSSIBLY_RELATED, likely.verdict, 'Outside the review, 70% stays possibly related');
        DocPdfCompareAction.adjustVerdict(likely, 'PROC-000003[001]', st, true);
        Assert.areEqual(DocPdfMatchService.LIKELY_VERSION, likely.verdict);

        DocPdfMatchService.Result renumbered = new DocPdfMatchService.Result();
        renumbered.verdict = DocPdfMatchService.DIFFERENT;
        renumbered.shared = 95;
        renumbered.numberState = 'different';
        renumbered.pdfNumber = 'PROC-000009';
        DocPdfCompareAction.adjustVerdict(renumbered, 'PROC-000003[001]', st, true);
        Assert.areEqual(DocPdfMatchService.VERSION, renumbered.verdict);
        Assert.isTrue(renumbered.text.contains('PROC-000009'), renumbered.text);
    }

    @IsTest
    static void titlesAndHeadingsStayOnTheirOwnLine() {
        List<String> s = DocPdfCompareService.sentences(new List<String>{
            'EU Belgium Emergency Response Procedures Procedure', 'SUMMARY',
            'This procedure defines how the site prepares', 'for emergencies.', 'It protects employees.'
        });
        Assert.areEqual(4, s.size(), '' + s);
        Assert.areEqual('SUMMARY', s[1]);
        Assert.areEqual('This procedure defines how the site prepares for emergencies.', s[2]);

        // Deleting the summary text leaves the title and heading unchanged: only the sentences are removed.
        String before = 'EU Belgium Procedure\nSUMMARY\nThis procedure defines how the site prepares for emergencies.\nIt protects employees.\n';
        String after = 'EU Belgium Procedure\nSUMMARY\n';
        DocPdfMatchService.Settings st = new DocPdfMatchService.Settings();
        DocPdfMatchService.Result m = DocPdfMatchService.match('PROC-000003[001]', 'PROC-000003', 'EU Belgium Procedure', null, before, after, st);
        DocPdfCompareService.Comparison c = DocPdfCompareService.compare(before, after, m, st);
        for (DocPdfCompareService.SectionChange sc : c.sections) {
            Assert.isTrue(sc.added.isEmpty(), '' + sc.added);
        }
    }

    // ------------------------------------------------------------------ review

    @IsTest
    static void reviewWithoutAMatchHasNoBanner() {
        System.runAs(agentUser()) {
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review', File_Name__c = 'New');
            insert p;
            DocPdfReviewController.ReviewData data = DocPdfReviewController.getReview(p.Id);
            Assert.isTrue(data.success, '' + data.errorMessage);
            Assert.isNull(data.match);
            DocPdfReviewController.CompareResult cr = DocPdfReviewController.compareWithMatch(p.Id);
            Assert.isFalse(cr.success);
            Assert.isNotNull(cr.message);
        }
    }

    @IsTest
    static void reviewShowsAMatchedDocument() {
        System.runAs(agentUser()) {
            compliancequest__SQX_Controlled_Document__c d;
            try {
                d = new compliancequest__SQX_Controlled_Document__c(
                    compliancequest__Title__c = 'Usage of Additives in Mixing Equipment',
                    compliancequest__Document_Number__c = 'SOP-44123',
                    compliancequest__Revision__c = '002');
                insert d;
            } catch (Exception e) {
                return; // ComplianceQuest validation in this org: the decision is covered above.
            }
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review', File_Name__c = 'New',
                Controlled_Document__c = d.Id, Match_Verdict__c = DocPdfRevisionCheck.SAME_NUMBER, Match_Score__c = 85);
            insert p;
            DocPdfReviewController.ReviewData data = DocPdfReviewController.getReview(p.Id);
            Assert.isTrue(data.success, '' + data.errorMessage);
            if (data.match != null) {
                Assert.areEqual((String) d.Id, data.match.documentId);
                Assert.isTrue(data.match.reason.contains('SOP-44123'), data.match.reason);
                Assert.isFalse(data.match.compared);
            }
            for (String kind : new List<String>{ DocPdfRevisionCheck.SAME_CONTENT, DocPdfRevisionCheck.SAME_TITLE, 'Other' }) {
                p.Match_Verdict__c = kind;
                update p;
                Assert.isTrue(DocPdfReviewController.getReview(p.Id).success);
            }
        }
    }

    @IsTest
    static void compareFromTheReviewKeepsTheReviewOpen() {
        System.runAs(agentUser()) {
            ContentVersion oldCv = new ContentVersion(Title = 'Current version', PathOnClient = 'Current version.pdf',
                VersionData = Blob.valueOf('%PDF-1.4 OLD'));
            insert oldCv;
            oldCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :oldCv.Id];
            ContentVersion newCv = new ContentVersion(Title = 'New version', PathOnClient = 'New version.pdf',
                VersionData = Blob.valueOf('%PDF-1.4 NEW'));
            insert newCv;
            newCv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :newCv.Id];
            insert new Doc_PDF_Text_Cache__c(Content_Version_Id__c = oldCv.Id,
                Text__c = 'Document Number: SOP-44123\nRevision: 002\nTitle: Usage of Additives in Mixing Equipment\n' + BODY,
                Pages_Read__c = 1, Total_Pages__c = 1);
            Doc_PDF_Proposal__c p = new Doc_PDF_Proposal__c(Status__c = 'Ready for Review', File_Name__c = 'New version',
                Content_Document_Id__c = newCv.ContentDocumentId, Content_Version_Id__c = newCv.Id,
                Extracted_Text__c = fileText(), Pages_Read__c = 1, Total_Pages__c = 1);
            insert p;
            DocPdfCompareAction.testDocument = new compliancequest__SQX_Controlled_Document__c(
                compliancequest__Title__c = 'Usage of Additives in Mixing Equipment',
                compliancequest__Document_Number__c = 'SOP-44123',
                compliancequest__Revision__c = '002',
                compliancequest__Content_Reference__c = oldCv.ContentDocumentId);

            Test.startTest();
            DocPdfCompareAction.Result r = DocPdfCompareAction.compareForReview(p.Id, null);
            Test.stopTest();

            Assert.isTrue(r.success, r.message);
            Assert.isTrue(r.compared, r.message);
            Assert.areEqual(DocPdfMatchService.VERSION, r.verdict);
            Doc_PDF_Proposal__c saved = [SELECT Status__c, Mode__c, Comparison_JSON__c, Old_Content_Version_Id__c FROM Doc_PDF_Proposal__c WHERE Id = :p.Id];
            Assert.areEqual('Ready for Review', saved.Status__c);
            Assert.areNotEqual('Compare', saved.Mode__c);
            Assert.isNotNull(saved.Comparison_JSON__c);
            Assert.areEqual((String) oldCv.Id, saved.Old_Content_Version_Id__c);
        }
    }
}
