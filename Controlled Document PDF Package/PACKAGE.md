# Enablement - Document Agent (managed package)

One package with both versions of the feature:
- **Agent**: Controlled Document Agent actions, upload / review / comparison components, Custom Lightning Types.
- **Screen flow**: `Controlled_Document_From_PDF` with `docPdfFlowUpload`, `docPdfFlowReview`, `docPdfFlowComparison`, `DocPdfFlowCreateAction`.
- Shared: all Doc PDF classes, objects, settings, the `Doc_From_PDF_Analyze` flow and the permission set `Doc_From_PDF_Agent_Access`.

| Setting | Value |
|---|---|
| Namespace | `enablement` (registered in a Developer Edition org, linked to the golden Dev Hub) |
| Dev Hub | `golden` |
| Package Id | `0Hofn0000001ZTZCA2` |
| Dependency | ComplianceQuest 16.0.0.40 (`04tRn000000qxC5IAI`); install orgs need this version or newer |

## Build a beta version
```
sf package version create --package "Enablement - Document Agent" --installation-key-bypass --code-coverage --wait 60 --target-dev-hub golden
```
Prints a Subscriber Package Version Id (04t...). Beta versions install only in scratch orgs and sandboxes, and cannot be upgraded in place.

## Install
```
sf package install --package 04t... --target-org cq-scratch-1 --wait 20 --no-prompt
```

## Release (when a beta has passed testing)
```
sf package version promote --package 04t... --target-dev-hub golden
```
Released versions install in any org and upgrade in place. Released `global` code cannot be removed afterwards.

## Not in the package (set up per org)
- Google Vision key: Named Credential `Google_Cloud_Vision`.
- Prompt template `Doc_PDF_Field_Suggestions` (Prompt Builder; text in `reference/Doc_PDF_Field_Suggestions_prompt.txt`).
- The agent itself: paste `Controlled_Document_Agent_Script.txt` in Agent Builder. In a packaged org, the three `complex_data_type_name` values use the `enablement__` prefix instead of `c__`.
- Released TMP templates (TMP-POL-000, TMP-PROC-000, TMP-WI-000) with status Current.
