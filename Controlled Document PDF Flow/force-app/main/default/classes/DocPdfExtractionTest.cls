@IsTest
private class DocPdfExtractionTest {

    // Text of pages 3, 4, 5 and 11 of the sample SOP (SOP-44123), as a PDF reader returns it,
    // watermark letters and bullet glyphs included.
    private static final String SAMPLE =
        'Document Number: SOP-44123\n' +
        'Revision: 002\n' +
        'Title: Usage of Additives in Mixing Equipment\n' +
        'Department: Quality Assurance\n' +
        '\n' +
        'Effective Date: 13-Nov-2024\n' +
        '\n' +
        '1. Purpose\n' +
        'The purpose of this SOP is to ensure the correct and consistent use of additives in concrete\n' +
        'mixing equipment to prevent issues such as mix instability, improper viscosity, or failure to\n' +
        'meet required standards. This procedure outlines the steps for selecting, measuring,\n' +
        'adding, and monitoring additives in concrete mixes to ensure high-quality, uniform results.\n' +
        'This update aims to address specific challenges with additives and provide detailed\n' +
        'guidance on how to use them properly in mixing equipment to ensure consistent concrete\n' +
        'quality and to avoid issues such as excessive thinning, delayed setting, or other\n' +
        'unexpected changes in the concrete\'s properties.\n' +
        '\n' +
        't\n' +
        'n\n' +
        '\n' +
        'e\n' +
        'rr\n' +
        '\n' +
        '2. Scope\n' +
        '\n' +
        'This SOP applies to all personnel involved in the preparation, mixing, and management of\n' +
        'concrete at any site where additives are used. It is intended for operators, site engineers,\n' +
        'quality control teams, and any individuals responsible for concrete batching, additive\n' +
        'management, and on-site testing.\n' +
        '\n' +
        'u\n' +
        '\n' +
        'Key Updates\n' +
        '\n' +
        'C\n' +
        '\n' +
        '1. Additive Compatibility and Selection\n' +
        'o\n' +
        '\n' +
        'Ensure compatibility testing of all additives before use, considering cement\n' +
        'type, environmental factors, and site-specific conditions.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Reference supplier-provided technical data sheets for guidance on additive\n' +
        'selection, and consult with the supplier when using a new type of additive.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'New Guidance: Avoid using multiple additives unless compatibility has been\n' +
        'confirmed through testing. Di erent additives may interact and cause\n' +
        'unexpected results.\n' +
        '\n' +
        '\n' +
        '\n' +
        'Document Number: SOP-44123\n' +
        'Revision: 002\n' +
        'Title: Usage of Additives in Mixing Equipment\n' +
        'Department: Quality Assurance\n' +
        '\n' +
        'Effective Date: 13-Nov-2024\n' +
        '\n' +
        '2. Additive Measurement and Dosage Controls\n' +
        'o\n' +
        '\n' +
        'New Requirement: All batching equipment must have automated dosage\n' +
        'systems to ensure precise measurement of additives, minimizing the risk of\n' +
        'human error. Manual dosing should only occur in the event of equipment\n' +
        'failure and must be logged with operator notes.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Updated Instructions: Before beginning any batch, verify that the dosage\n' +
        'equipment is properly calibrated. Check calibration daily, or before each\n' +
        'batch if multiple di erent additive types are used.\n' +
        '\n' +
        't\n' +
        'n\n' +
        '\n' +
        '3. Mixing Process with Additives\n' +
        'o\n' +
        '\n' +
        'Updated Instructions: Introduce additives only after initial wet mixing of\n' +
        'water, cement, and aggregates to ensure that the concrete base has\n' +
        'developed the correct consistency. This minimizes the risk of improper\n' +
        'dispersion.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Additives should be added slowly and over time, while the mixer continues to\n' +
        'operate. Allow time for thorough mixing between each additive.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'New Requirement: Ensure that the mixing process accounts for the time\n' +
        'required for the additives to integrate fully with the cementitious materials.\n' +
        'Refer to manufacturer recommendations for specific additives.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'New Step: After additives are fully integrated, allow an additional 2-3\n' +
        'minutes of mixing to ensure homogeneity across the batch.\n' +
        '\n' +
        'e\n' +
        'rr\n' +
        '\n' +
        'u\n' +
        '\n' +
        'C\n' +
        '\n' +
        'Environmental Considerations for Additives\n' +
        'o\n' +
        '\n' +
        'Expanded Section: Adjust additive dosages depending on temperature,\n' +
        'humidity, and weather conditions. For instance:\n' +
        '*\n' +
        '\n' +
        'In hot climates, avoid high amounts of water reducers or accelerators\n' +
        'as they can lead to rapid thinning and early setting.\n' +
        '\n' +
        '*\n' +
        '\n' +
        'In colder climates, extend mixing times and adjust the dosage to\n' +
        'prevent delayed setting or premature sti ening.\n' +
        '\n' +
        '\n' +
        '\n' +
        'Document Number: SOP-44123\n' +
        'Revision: 002\n' +
        'Title: Usage of Additives in Mixing Equipment\n' +
        'Department: Quality Assurance\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Effective Date: 13-Nov-2024\n' +
        '\n' +
        'New Procedure: Implement on-site weather monitoring systems to\n' +
        'continuously track environmental conditions and adjust additive dosages\n' +
        'accordingly in real-time.\n' +
        '\n' +
        'On-site Testing After Adding Additives\n' +
        'o\n' +
        '\n' +
        'New Testing Requirement: In addition to the slump test, conduct a viscosity\n' +
        'or flow table test after mixing to check for uniformity and confirm that the\n' +
        'additives have not over-thinned the mix.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Periodically take samples from the batch and test after 30, 60, and 90\n' +
        'minutes to ensure that the additives behave as expected over time.\n' +
        '\n' +
        't\n' +
        'n\n' +
        '\n' +
        'Documentation and Record Keeping for Additive Use\n' +
        '\n' +
        'e\n' +
        'rr\n' +
        '\n' +
        'o\n' +
        '\n' +
        'Expanded Record-Keeping Guidelines: Log the type, amount, and time of\n' +
        'additive introduction into the mixing equipment, along with environmental\n' +
        'data at the time of batching.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'New Requirement: Document and store all calibration records of dosing\n' +
        'equipment for each batch.\n' +
        '\n' +
        'o\n' +
        '\n' +
        'For any batch where additives are manually measured, include detailed\n' +
        'operator notes on the procedure followed and the reasoning for manual\n' +
        'dosing.\n' +
        '\n' +
        'C\n' +
        '\n' +
        'u\n' +
        '\n' +
        '3. Responsibilities\n' +
        '*\n' +
        '\n' +
        'Operator: Responsible for measuring and adding the correct amount of additives\n' +
        'according to the approved mix design and this SOP.\n' +
        '\n' +
        '*\n' +
        '\n' +
        'Site Engineer: Ensures the correct additives are used based on site-specific\n' +
        'conditions and concrete specifications.\n' +
        '\n' +
        '*\n' +
        '\n' +
        'Quality Control Team: Verifies additive compatibility and dosage, ensures\n' +
        'compliance with mix design, and monitors concrete performance after additives are\n' +
        'incorporated.\n' +
        '\n' +
        '\n' +
        '\n' +
        'Document Number: SOP-44123\n' +
        'Revision: 002\n' +
        'Title: Usage of Additives in Mixing Equipment\n' +
        'Department: Quality Assurance\n' +
        '\n' +
        'Effective Date: 13-Nov-2024\n' +
        '\n' +
        'Author:\n' +
        'Joanne StAndre\n' +
        'Document Category: Procedure\n' +
        'Document Status:\n' +
        'Current\n' +
        'Date Approved:\n' +
        '14-Oct-2024\n' +
        'Expiration Date:\n' +
        '\n' +
        'Approval History\n' +
        'Step\n' +
        '\n' +
        'Name of Approver\n' +
        '\n' +
        'Approval Date\n' +
        '\n' +
        'Approval Step 1\n' +
        '\n' +
        'Bob Brickell\n' +
        '\n' +
        '14-Oct-2024 1:34 PM\n' +
        '\n' +
        'Approval Step 1\n' +
        '\n' +
        'Joanne StAndre\n' +
        '\n' +
        '14-Oct-2024 1:34 PM\n' +
        '\n' +
        't\n' +
        'n\n' +
        '\n' +
        'Revision History\n' +
        'Revision Number\n' +
        '\n' +
        'Changes\n' +
        '\n' +
        '001\n' +
        '\n' +
        'N/A\n' +
        '\n' +
        '14-Oct-2024\n' +
        '\n' +
        'u\n' +
        '\n' +
        'Related Documents\n' +
        '\n' +
        'C\n' +
        '\n' +
        'Document Number\n' +
        '\n' +
        'Title\n' +
        '\n' +
        'APROC-9648[004]\n' +
        '\n' +
        'Cleaning Procedure\n' +
        '\n' +
        'Requirements\n' +
        '\n' +
        'e\n' +
        'rr\n' +
        '\n' +
        'Effective Date\n' +
        '\n' +
        'Job Function\n' +
        '\n' +
        'Description\n' +
        '\n' +
        'Quality Assurance\n' +
        '\n' +
        'All Quality Assurance personnel\n' +
        '\n' +
        'Quality Control\n' +
        '\n' +
        'All Quality Control Personnel\n' +
        '\n' +
        '\n';

    private class VisionMock implements HttpCalloutMock {
        Integer status;
        Integer calls = 0;
        VisionMock(Integer status) {
            this.status = status;
        }
        public HttpResponse respond(HttpRequest req) {
            calls++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setHeader('Content-Type', 'application/json');
            if (status != 200) {
                res.setBody('{"error":{"code":403,"message":"The request is missing a valid API key."}}');
                return res;
            }
            // 7-page file: first call returns pages 1-5, second call pages 6-7.
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            Map<String, Object> request = (Map<String, Object>) ((List<Object>) body.get('requests'))[0];
            List<Object> pages = (List<Object>) request.get('pages');
            List<Object> pageResponses = new List<Object>();
            for (Object p : pages) {
                String t = Integer.valueOf(p) == 1 ? SAMPLE : 'Page ' + p;
                pageResponses.add(new Map<String, Object>{ 'fullTextAnnotation' => new Map<String, Object>{ 'text' => t } });
            }
            res.setBody(JSON.serialize(new Map<String, Object>{
                'responses' => new List<Object>{
                    new Map<String, Object>{ 'totalPages' => 7, 'responses' => pageResponses }
                }
            }));
            return res;
        }
    }

    private static ContentVersion makeFile(String path) {
        ContentVersion cv = new ContentVersion(Title = 'Sample', PathOnClient = path, VersionData = Blob.valueOf('%PDF-1.4 test'));
        insert cv;
        return cv;
    }

    @IsTest
    static void parsesTheSampleSop() {
        DocPdfFieldParser.Parsed p = DocPdfFieldParser.parse(SAMPLE);
        Assert.areEqual('SOP-44123', p.documentNumber);
        Assert.areEqual('002', p.revision);
        Assert.areEqual('Usage of Additives in Mixing Equipment', p.title);
        Assert.areEqual('Quality Assurance', p.department);
        Assert.areEqual('2024-11-13', p.effectiveDate);
        Assert.areEqual('Joanne StAndre', p.author);
        Assert.areEqual('Procedure', p.documentCategory);
        Assert.areEqual('Current', p.documentStatus);
        Assert.areEqual('2024-10-14', p.dateApproved);
        Assert.isNull(p.expirationDate);
        Assert.areEqual('The purpose of this SOP is to ensure the correct and consistent use of additives in concrete mixing equipment to prevent issues such as mix instability, improper viscosity, or failure to meet required standards.', p.purposeSummary);
        Assert.areEqual(new List<String>{
            'Additive Compatibility and Selection', 'Additive Measurement and Dosage Controls',
            'Mixing Process with Additives', 'Environmental Considerations for Additives',
            'On-site Testing After Adding Additives', 'Documentation and Record Keeping for Additive Use'
        }, p.keyUpdateHeadings);
        Assert.isTrue(p.hasMajorMarkers);
        Assert.isTrue(p.changeMarkers.contains('New requirement'), String.valueOf(p.changeMarkers));
        Assert.areEqual(new List<String>{ 'APROC-9648[004]' }, p.relatedDocumentNumbers);
        Assert.areEqual(new List<String>{ 'Quality Assurance', 'Quality Control' }, p.jobFunctions);
        Assert.areEqual(new List<String>{ '001' }, p.revisions);
    }

    @IsTest
    static void handlesOtherDateFormatsAndBlanks() {
        Assert.areEqual('2024-11-13', DocPdfFieldParser.toIsoDate('13 November 2024'));
        Assert.areEqual('2024-11-13', DocPdfFieldParser.toIsoDate('2024-11-13'));
        Assert.areEqual('2024-11-13', DocPdfFieldParser.toIsoDate('11/13/2024'));
        Assert.isNull(DocPdfFieldParser.toIsoDate('Approval History'));
        Assert.isNull(DocPdfFieldParser.parse('').documentNumber);
        Assert.isNull(DocPdfFieldParser.asHeading('Ensure compatibility testing of all additives, before use'));
        Assert.areEqual('One.', DocPdfFieldParser.firstSentence('One. Two.', 100));
    }

    @IsTest
    static void readsEveryPageFiveAtATime() {
        ContentVersion cv = makeFile('sample.pdf');
        VisionMock mock = new VisionMock(200);
        Test.setMock(HttpCalloutMock.class, mock);
        ExtractPdfTextSyncAction.Request req = new ExtractPdfTextSyncAction.Request();
        req.contentVersionId = cv.Id;
        Test.startTest();
        ExtractPdfTextSyncAction.Result r = ExtractPdfTextSyncAction.run(new List<ExtractPdfTextSyncAction.Request>{ req })[0];
        Test.stopTest();
        Assert.isTrue(r.success, '' + r.message);
        Assert.areEqual(7, r.pagesRead);
        Assert.areEqual(7, r.totalPages);
        Assert.isTrue(r.extractedText.contains('SOP-44123'));
        Assert.isTrue(r.extractedText.contains('Page 7'));
    }

    @IsTest
    static void explainsAKeyProblem() {
        ContentVersion cv = makeFile('sample.pdf');
        Test.setMock(HttpCalloutMock.class, new VisionMock(403));
        Test.startTest();
        GoogleVisionPdfService.Extraction ex = GoogleVisionPdfService.extract(cv.Id);
        Test.stopTest();
        Assert.isFalse(ex.success);
        Assert.isTrue(ex.message.contains('Named Credential'), '' + ex.message);
        Assert.isTrue(ex.message.contains('missing a valid API key'), '' + ex.message);
    }

    @IsTest
    static void rejectsMissingAndNonPdfFiles() {
        Assert.isFalse(GoogleVisionPdfService.extract(null).success);
        ContentVersion txt = makeFile('notes.txt');
        GoogleVisionPdfService.Extraction ex = GoogleVisionPdfService.extract(txt.Id);
        Assert.isFalse(ex.success);
        Assert.isTrue(ex.message.contains('not a PDF'), '' + ex.message);
        ExtractPdfTextSyncAction.Request req = new ExtractPdfTextSyncAction.Request();
        req.contentVersionId = 'not-an-id';
        Assert.isFalse(ExtractPdfTextSyncAction.run(new List<ExtractPdfTextSyncAction.Request>{ req })[0].success);
    }
}
