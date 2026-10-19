# Agent setup: Controlled Document Agent

The metadata deploy (README) carries everything the agent calls. The agent itself comes from the script `Controlled_Document_Agent_Script.txt` (also here as `Controlled_Document_Agent.agent`).

## 1. Before creating or updating the agent
1. Deploy the package and assign `Doc_From_PDF_Agent_Access` to yourself and the test users.
2. Set the Google Vision key on the `Google_Cloud_Vision` Named Credential (README).
3. Users also need their usual ComplianceQuest permissions to create and read Controlled Documents and their files.

## 2. Create or update the agent
1. New agent: Setup > Agentforce Agents > **New Agent** > Agentforce Employee Agent, name **Controlled Document Agent**, API name `Controlled_Document_Agent`.
2. In Agentforce Builder, switch to the script view, replace the script with `Controlled_Document_Agent_Script.txt`, and save.
3. Check the actions resolved:

   | Action | Target | Component |
   | --- | --- | --- |
   | Select PDF | Apex `DocPdfSelectFileAction` | Input `selection`: `c__docPdfFileSelectionType` (upload) |
   | Analyze PDF | Flow `Doc_From_PDF_Analyze` | None; the agent relays `summary` |
   | Review and Create | Apex `DocPdfCreateDocumentAction` | Input `review`: `c__docPdfReviewType` (review) |
   | Compare PDF | Apex `DocPdfCompareAction` | Output `comparison`: `c__docPdfComparisonType` (comparison) |

4. **Commit and activate** a new version. Components may not render while the agent is a draft.
5. Give users access to the agent, and add it to the Controlled Document record page's Agentforce panel so it receives the record Id.

## 3. Conversations

**Create**: "Create a controlled document from a PDF" > upload or pick a PDF > the agent reads it and shows the review straight away (Needs review, Ready, Set automatically) > decide each highlighted field, wait for "Choices saved", Submit > the Draft is created with the PDF as Primary Content.

**Compare** (on a Controlled Document record): "Compare a new PDF with this document" > upload or pick the new PDF > Submit > the agent reads both PDFs and shows the comparison:
- **Version / Rewritten / Likely Version**: verdict with reasons, then the summary, suggested Change Scope, suggested Changes text (Copy), header values and sections you can expand.
- **Possibly Related**: the agent asks "Compare anyway?"; yes compares, with a note.
- **Different**: not compared; the agent offers to compare with a document matching the PDF's number or title, or to create a new document from the PDF.

## 4. Test script (dev)

Create: `Usage of Additives in Mixing Equipment.pdf` (11 pages) gives Title and Document Category Ready, Description Needs review, Record Type and Primary Content set automatically.

Compare, on SOP-44123[002] (created from that PDF, so its Primary Content is the PDF):
1. The same PDF: "That is the same file as the Primary Content", nothing compared.
2. A copy of the PDF with an edited sentence and a higher revision: Version, newer, 1 changed section.
3. A different SOP: Different, with the option to compare with the matching document if it exists, or create a new one.

Check the Doc PDF Proposal afterwards: Mode Compare, Status Compared, Match Verdict, Text Shared %, Summary.

## 5. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| "Google Vision rejected the request (403)" | Named Credential key not set, or Generate Authorization Header ticked |
| A component does not appear | Agent not activated, or the Lightning types / LWCs not deployed |
| "Open the Controlled Document you want to compare with…" | The agent did not get a record Id: open it from the Controlled Document page, or give the document number |
| "… has no PDF to compare with" | The Primary Content is missing or not a PDF, and there is no PDF Secondary Content |
| Comparison times out | Two long PDFs: lower `GoogleVisionPdfService.maxPages` |
| The agent asks "Ready to review?" instead of showing the review | Old script: paste the current one and activate a new version |
| Agent says created, but nothing was | Old script; the proposal keeps the review, say "show the review" |
| "ComplianceQuest did not accept the new document: …" | A CQ validation rule; change that value in the review and submit again |
