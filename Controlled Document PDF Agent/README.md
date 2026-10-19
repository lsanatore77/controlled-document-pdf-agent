# Controlled Document PDF Agent

An Agentforce employee agent (**Controlled Document Agent**, `Controlled_Document_Agent`) for ComplianceQuest Controlled Documents. It does two things with a PDF:

1. **Create**: reads the PDF with Google Vision, recommends a value for each field set up in custom metadata, lets the user accept, edit or clear each value in a review component, then creates the Controlled Document as a Draft with the PDF as its Primary Content.
2. **Compare**: on an existing Controlled Document, checks whether a new PDF is a version of it or a different document, then compares it with the document's Primary Content and summarizes the differences (summary, suggested Change Scope, suggested Changes text, header changes, section-by-section changes).

The agent script is `Controlled_Document_Agent_Script.txt` (also in `reference/Controlled_Document_Agent.agent`). Setup steps for the agent are in `reference/AGENT_SETUP.md`.

## What is in it

| Area | Metadata |
|---|---|
| Reading PDFs | `GoogleVisionPdfService` (Google Vision files:annotate, 5 pages per request, up to 30 pages), `ExtractPdfTextSyncAction`; Named Credential `Google_Cloud_Vision` (in the org, not in this package) |
| Choosing the PDF | `docPdfUpload` LWC + `docPdfFileSelectionType`, `DocPdfUploadController`, `DocPdfSelectFileAction`, `DocPdfResolveProposalAction`, `DocPdfFileSelection` |
| Create: recommendations | Flow `Doc_From_PDF_Analyze`, `DocPdfBuildRecommendationsAction`, `DocPdfRecommendationBuilder`, `DocPdfFieldParser`, custom metadata `Doc_PDF_Field_Config__mdt` (4 records) |
| Create: review and create | `docPdfReview` LWC + `docPdfReviewType`, `DocPdfReviewController`, `DocPdfReview`, `DocPdfCreateDocumentAction` |
| Compare | `DocPdfCompareAction`, `DocPdfMatchService` (version check), `DocPdfCompareService` (comparison and summary), `docPdfComparison` LWC + `docPdfComparisonType`, `DocPdfComparisonController`, `DocPdfComparisonView`, custom metadata `Doc_PDF_Agent_Setting__mdt` (record Default) |
| Data | `Doc_PDF_Proposal__c` (one run: the file, the text, the result; Mode Create or Compare), `Doc_PDF_Field__c` (one recommended field), `Doc_PDF_Text_Cache__c` (text read from a file version, so the existing document is not re-read for every comparison) |
| Access | Permission set `Doc_From_PDF_Agent_Access` |
| Tests | `DocPdfAgentTest`, `DocPdfExtractionTest`, `DocPdfCompareTest` |

## Deploy

From this folder, with the Salesforce CLI logged in to the target org:

```
sf project deploy start --manifest manifest/package.xml --test-level NoTestRun
```

Sandboxes can skip tests. For production, run the three test classes:

```
sf project deploy start --manifest manifest/package.xml --test-level RunSpecifiedTests --tests DocPdfAgentTest DocPdfExtractionTest DocPdfCompareTest
```

Then:
1. Assign **Doc_From_PDF_Agent_Access** to the users (they also need their normal ComplianceQuest permissions).
2. Paste `Controlled_Document_Agent_Script.txt` into the agent in Agentforce Builder, save, commit and activate a new version (`reference/AGENT_SETUP.md`).
3. Start a new conversation to test; an open one keeps the old version.

## Google Vision key

The code holds no API key. It sends the key from the `Google_Cloud_Vision` Named Credential as the `X-Goog-Api-Key` header. Named Credential settings: Password Authentication, any username (e.g. `apikey`), password = the API key, **Generate Authorization Header unticked**, Allow Merge Fields in HTTP Header ticked. A 403 from Google means the key is missing or wrong.

## Create: which fields (custom metadata, no deploy needed)

Setup > Custom Metadata Types > **Doc PDF Field Config** > Manage Records. One record per field:

| Setting | Meaning |
|---|---|
| Field API Name | The Controlled Document field (`RecordTypeId` for the record type, `OwnerId` for the owner) |
| Field Label | Optional label in the review |
| Active | Uncheck to leave the field out |
| Sort Order | Position in the review |
| Required | Blocks creation while blank |
| Editable | Uncheck to show the value as fixed |
| Value Source | Labeled Value, First Sentence of Section, Whole Section, Picklist Match, Lookup Match, Fixed Value, User Input |
| PDF Label or Section | The label without the colon (`Title`) or the section heading (`Purpose`) |
| Match Rules | Picklist Match: one `regular expression => value` per line, tried when the label has no value |
| Default Value | Fixed value, or the fallback. Record type: developer name. Lookups: record Id or Name |
| Help Text | The note under the field in the review |

Shipped records: Document Title (Labeled Value `Title`, required), Description (first sentence of `Purpose`), Document Category (Picklist Match `Document Category`, rule `SOP` from the document number), Record Type (Fixed Value `Controlled_Document`, not editable).

The PDF is always set as the document's **Primary Content** (`compliancequest__Content_Reference__c` = the file, check-in method Manual) and linked to the record. If ComplianceQuest rejects a record with no Document Number, the create step retries once with `TEST-yyyyMMdd-HHmmss` (test org behavior).

## Compare: how it works

1. The user is on a Controlled Document and asks to compare a new PDF (or names a document number). The agent uses the page's record Id.
2. The user uploads or picks the new PDF (the same upload component as Create).
3. `DocPdfCompareAction` finds the document's **Primary Content** PDF (else its Secondary Content when that is a PDF), reads both with Google Vision (the existing document's text is cached per file version), then:
4. **Version check** (`DocPdfMatchService`, rules only):

   | Document number | Text shared | Result |
   |---|---|---|
   | Same | ≥ Version min (40%) | **Version**: compared |
   | Same | below it | **Rewritten** (same document, heavily changed): compared, with a warning |
   | Not in the PDF | ≥ Likely min (60%) and title matches (≥ 60% of words) | **Likely Version**: compared |
   | Not in the PDF | ≥ Related min (25%) | **Possibly Related**: the agent asks whether to compare anyway |
   | Different, or shared below Related min | | **Different**: not compared; the agent offers a document matching the PDF's number or title, or creating a new document from the PDF |

   The revision decides the wording: newer, same (possible duplicate) or older.
5. **Comparison** (`DocPdfCompareService`): both texts are cleaned (page headers, footers, page numbers, watermark letters, contents lines), split into sections by heading, matched by heading and compared sentence by sentence. Header values (Document Number, Revision, Title, Effective Date, Document Category, Department) are compared too.
6. **Summary**: written by rules (what changed, added and removed; suggested Change Scope: Major when sections were added or removed or new text says must/shall/required, else Minor; suggested Changes text). Optional: set **Summary Prompt Template** on the Default setting to a Prompt Builder flex template with one text input named `Differences`, and its answer replaces the rules summary (the rules summary stays as the fallback).
7. The result is saved on the Doc PDF Proposal (Mode Compare, Status Compared, verdict, % shared, JSON, summary) and shown by the comparison component. **Nothing on the Controlled Document changes.**

Settings (Setup > Custom Metadata Types > **Doc PDF Agent Setting** > Default): Version / Likely Version / Related minimum % shared, Title match minimum %, the PDF labels for document number, title and revision, and the optional prompt template.

## Known limits

- Up to 30 pages per PDF (`GoogleVisionPdfService.maxPages`); both PDFs share the 120-second callout limit in one comparison. Very long documents would need a background job (not built).
- Word Primary Content cannot be read (Google Vision reads PDFs). Compare uses a PDF Secondary Content when there is one.
- Section matching relies on headings ("1. Purpose", "Key Updates", known names). Documents without headings are compared as one block.
- Compare does not start a revision or write Changes / Change Scope; that waits for the "update existing records" work.
- The text cache is private per user.

## Change log

- 2026-10-19: Compare a PDF with an existing Controlled Document (version check, comparison, summary, comparison component, agent script path). Review opens straight after the analysis.
- 2026-10-18: Fields set up in custom metadata; PDF set as Primary Content; test document number fallback. Review screen saves each choice; create reads the saved choices. Upload component saves the chosen PDF; Analyze PDF finds the proposal without an Id.
- 2026-10-17: First version (create from PDF).
