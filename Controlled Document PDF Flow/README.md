# Controlled Document PDF Flow

The **Screen Flow** version of the Controlled Document PDF Agent, for ComplianceQuest Controlled Documents. No Agentforce needed. One flow, **Controlled Document from PDF** (`Controlled_Document_From_PDF`), embedded on a page:

1. **Create**: the user uploads or picks a PDF; Google Vision reads it; the flow shows a recommended value for each field set up in custom metadata; the user accepts, edits or clears each one and selects Submit; the flow creates the Controlled Document as a Draft with the PDF as its Primary Content and links to it.
2. **Compare** (on a Controlled Document record page): the user picks "Compare a new PDF with this document", uploads the new PDF, and sees whether it is a version of this document or a different one, then what changed (summary, suggested Change Scope and Changes text, header changes, section by section).

It uses the same Apex, data and settings as the agent version (`Controlled Document PDF Agent` folder, `main` branch). This folder is standalone: deploy it on its own.

## Flow path

```
Start
 ├─ on a record ─> Choose Action (Compare / Create)
 └─ no record ───> Upload PDF
Upload PDF ─> Compare?  ─ yes ─> Compare PDF ─> Comparison screen (Compare anyway? loops back)
                        └ no ──> Read PDF (subflow Doc_From_PDF_Analyze) ─> Review Fields ─ Submit ─> Create Document
                                                                             ^── fields still undecided ──┘
                                                                             Created ─> Done (link to the record)
Any failure ─> "Something went wrong" screen with the message
```

## What is in it

| Area | Metadata |
|---|---|
| The flow | `Controlled_Document_From_PDF` (Screen Flow), subflow `Doc_From_PDF_Analyze` |
| Flow screen components | `docPdfFlowUpload` (upload or pick a PDF; Next waits until it is saved), `docPdfFlowReview` (wraps `docPdfReview`), `docPdfFlowComparison` (wraps `docPdfComparison`) |
| Flow action | `DocPdfFlowCreateAction` (proposal Id + decisions JSON, runs `DocPdfCreateDocumentAction`) |
| Reading PDFs | `GoogleVisionPdfService`, `ExtractPdfTextSyncAction`; Named Credential `Google_Cloud_Vision` (created in the org, not in this package) |
| Create | `DocPdfUploadController`, `DocPdfSelectFileAction`, `DocPdfResolveProposalAction`, `DocPdfBuildRecommendationsAction`, `DocPdfRecommendationBuilder`, `DocPdfFieldParser`, `DocPdfReviewController`, `DocPdfCreateDocumentAction`, custom metadata `Doc_PDF_Field_Config__mdt` |
| Compare | `DocPdfCompareAction`, `DocPdfMatchService`, `DocPdfCompareService`, `DocPdfComparisonController`, custom metadata `Doc_PDF_Agent_Setting__mdt` (Default) |
| Data | `Doc_PDF_Proposal__c`, `Doc_PDF_Field__c`, `Doc_PDF_Text_Cache__c` |
| Access | Permission set `Doc_From_PDF_Agent_Access` (now also the flow and `DocPdfFlowCreateAction`) |
| AI suggestions | `DocPdfAiSuggestions`, Prompt Builder template `Doc_PDF_Field_Suggestions` (created in the org: `reference/Doc_PDF_Field_Suggestions_prompt.txt`), fields AI Answer (field config), Field Prompt Template (setting), AI Status (proposal) |
| Tests | `DocPdfAgentTest`, `DocPdfExtractionTest`, `DocPdfCompareTest`, `DocPdfFlowTest`, `DocPdfAiTest` |

Not in this folder (agent only): the agent script and the three Lightning Types. `docPdfReview` and `docPdfComparison` are included but not exposed; the flow components use them. Do not deploy this folder over an org that runs the agent version: it removes the agent targets from those two components.

## Deploy

From this folder, logged in to the target org (`testorg` is your alias):

```
sf project deploy start --manifest manifest/package.xml --target-org testorg
```

Production (validate, then quick deploy with the job Id it prints):

```
sf project deploy validate --manifest manifest/package.xml --target-org testorg --test-level RunSpecifiedTests --tests DocPdfAgentTest DocPdfExtractionTest DocPdfCompareTest DocPdfFlowTest DocPdfAiTest DocPdfRevisionCheckTest
sf project deploy quick --job-id 0Af... --target-org testorg
```

Then:
1. Activate **Doc From PDF Analyze** and **Controlled Document from PDF** (Setup > Flows) if they arrived inactive (production deploys flows inactive).
2. Create the `Google_Cloud_Vision` Named Credential (below).
3. Assign **Doc_From_PDF_Agent_Access** to the users.
4. Add the flow to pages in Lightning App Builder: drag the standard **Flow** component, choose **Controlled Document from PDF**, and on a Controlled Document record page tick **Pass record ID into this variable** (`recordId`). On a Home or App page leave it unticked: the flow goes straight to Create.

## AI suggestions (with rule fallback)

Title, Description, Document Category and Template can be suggested by AI first, with the rules below as the fallback:

1. After Google Vision reads the PDF, the text (first 30,000 characters) goes to a Prompt Builder flex template, **Doc_PDF_Field_Suggestions**, which answers with JSON: title, description, documentType (Policy, Procedure, Work Instruction, Other). The prompt text and setup steps are in `reference/Doc_PDF_Field_Suggestions_prompt.txt`.
2. Each field with an **AI Answer** in Doc PDF Field Config (title, description, documentType) uses the AI value first. AI values are always left for review and are labeled **Written by AI**.
3. If AI is off (no template set, template missing, Einstein off), fails, or gives a value that does not fit the field (not a picklist value, no such template), the field's Value Source rules run, as before. The note under the field says why.
4. The top of the review shows **AI suggestions: on** or **AI suggestions: off** with the reason. The same text is saved on the proposal (AI Status).

Turn AI off by clearing **Field Prompt Template** on Doc PDF Agent Setting (Default), or by clearing a field's AI Answer.

**Template (numbering).** The Template row picks the CQ template from the AI document type (Policy → TMP-POL-000, Procedure → TMP-PROC-000, Work Instruction → TMP-WI-000) or, as the fallback, by rule from the text. CQ then numbers the document from the template (POL-000001 and so on); the PDF stays the Primary Content. Change the template numbers in the Template row's Match Rules if your templates are numbered differently. Only Template Document records are offered.

**Title fallback.** Default Value `{First Line}` on the Title row: when there is no "Title:" label, the first line of the PDF that reads like a title is used.

**Description fallback.** The Purpose section is also found under headings such as "POLICY PURPOSE" or "Purpose of this Procedure", and reading stops at the next all-capitals heading.

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

1. On a Controlled Document page the user chooses "Compare a new PDF with this document". The flow passes the page's record Id.
2. The user uploads or picks the new PDF (the same upload screen as Create).
3. `DocPdfCompareAction` finds the document's **Primary Content** PDF (else its Secondary Content when that is a PDF), reads both with Google Vision (the existing document's text is cached per file version), then:
4. **Version check** (`DocPdfMatchService`, rules only):

   | Document number | Text shared | Result |
   |---|---|---|
   | Same | ≥ Version min (40%) | **Version**: compared |
   | Same | below it | **Rewritten** (same document, heavily changed): compared, with a warning |
   | Not in the PDF | ≥ Likely min (60%) and title matches (≥ 60% of words) | **Likely Version**: compared |
   | Not in the PDF | ≥ Related min (25%) | **Possibly Related**: the comparison screen offers "Compare anyway" |
   | Different, or shared below Related min | | **Different**: not compared; the screen shows a document matching the PDF's number or title, or creating a new document from the PDF |

   The revision decides the wording: newer, same (possible duplicate) or older.
5. **Comparison** (`DocPdfCompareService`): both texts are cleaned (page headers, footers, page numbers, watermark letters, contents lines), split into sections by heading, matched by heading and compared sentence by sentence. Header values (Document Number, Revision, Title, Effective Date, Document Category, Department) are compared too.
6. **Summary**: written by rules (what changed, added and removed; suggested Change Scope: Major when sections were added or removed or new text says must/shall/required, else Minor; suggested Changes text). Optional: set **Summary Prompt Template** on the Default setting to a Prompt Builder flex template with one text input named `Differences`, and its answer replaces the rules summary (the rules summary stays as the fallback).
7. The result is saved on the Doc PDF Proposal (Mode Compare, Status Compared, verdict, % shared, JSON, summary) and shown by the comparison component. **Nothing on the Controlled Document changes.**

Settings (Setup > Custom Metadata Types > **Doc PDF Agent Setting** > Default): Version / Likely Version / Related minimum % shared, Title match minimum %, the PDF labels for document number, title and revision, and the optional prompt template.

## Word files, best-fit template and numbering

- **Word (.docx) uploads.** The upload accepts PDF and Word. A .docx file is read in Apex (`DocPdfDocxReader`: it unzips the file and reads `word/document.xml`), with no Google Vision call. PDFs still go through Google Vision. Old .doc files are refused with a "save as .docx" message. Word files over 4 MB (`DocPdfDocxReader.MAX_BYTES`) are refused with a "compress the pictures" message. The uploaded file, Word or PDF, becomes the Primary Content unchanged.
- **Category and best-fit template.** The Category comes from AI when it is on. Otherwise, after a "Document Category:" label, the document's headings are compared with each template's sections (Category Templates, below) and the closest one wins, before the keyword Match Rules.
- **Template follows the Category.** The Template row is the released (Current) template set up for the Category. When the document is created, the Template is taken from the final Category, unless the user picked one themselves (Edit).
- **Numbering.** ComplianceQuest numbers the document from the template. With no released template, or if ComplianceQuest leaves the number blank, the number is the Category prefix plus the next free number (POL-000004), checked again at Submit across all documents. A document is never saved without a number (the old TEST number is gone).
- **Description.** AI writes a 2-3 sentence summary. When AI is off, the first 2-3 sentences of the first section found among Purpose, Policy Purpose, Summary, Objective, Scope (Doc PDF Field Config, Description, PDF Label; several headings separated by ;).

**Category Templates** (Setup, Custom Metadata Types, Doc PDF Agent Setting, Default): one line per category.

```
Category | Template Document Number | Number Prefix | section headings separated by ;
Policy | TMP-POL-000 | POL | Policy Purpose; Principles of this Policy; Definitions; Related
Procedure | TMP-PROC-000 | PROC | Summary; Requirements; Procedures; Validation
Work Instruction | TMP-WI-000 | WI | Objective; Scope; Required Personal Protective Equipment (PPE); Procedure; Emergency Procedures
SOP | TMP-PROC-000 | SOP | Purpose; Scope; Responsibilities; Procedure; References
```

Templates must be released (Document Status Current) to be used; ComplianceQuest refuses draft templates.

## Known limits

- Up to 30 pages per PDF (`GoogleVisionPdfService.maxPages`); both PDFs share the 120-second callout limit in one comparison. Very long documents would need a background job (not built).
- Word files are read for text only: pictures, text inside pictures, headers and footers are not used for suggestions (they stay in the file). Files over 4 MB are not read; reading large files in the background is planned.
- Compare reads PDF or Word Primary Content (else a PDF or Word Secondary Content).
- Section matching relies on headings ("1. Purpose", "Key Updates", known names). Documents without headings are compared as one block.
- Compare does not start a revision or write Changes / Change Scope; that waits for the "update existing records" work.
- The text cache is private per user.

## Change log

- 2026-10-29 (Word): Word (.docx) uploads read in Apex; best-fit template from section headings; Template follows the Category; numbering from the template, else Category prefix plus the next free number (no TEST numbers); 2-3 sentence description fallback; long-text custom metadata read with SOQL (Match Rules past 255 characters now apply).
- 2026-10-29: AI suggestions first (Prompt Builder template Doc_PDF_Field_Suggestions) with the rules as fallback, AI on/off shown in the review; Template chosen from the document type (CQ numbering); Title falls back to the PDF's first line; Purpose found under headings like POLICY PURPOSE; Category rules for Policy / Procedure / Work Instruction; retry with a clean record when the test number is used.
- 2026-10-28: Screen Flow version (`screen-flow` branch): flow `Controlled_Document_From_PDF`, components `docPdfFlowUpload`, `docPdfFlowReview`, `docPdfFlowComparison`, action `DocPdfFlowCreateAction`, test `DocPdfFlowTest`. No Agentforce needed.
- 2026-10-19: Compare a PDF with an existing Controlled Document (version check, comparison, summary, comparison component, agent script path). Review opens straight after the analysis.
- 2026-10-18: Fields set up in custom metadata; PDF set as Primary Content; test document number fallback. Review screen saves each choice; create reads the saved choices. Upload component saves the chosen PDF; Analyze PDF finds the proposal without an Id.
- 2026-10-17: First version (create from PDF).
