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
| Dependency | ComplianceQuest 15.6.0.3 (`04tKg000000xAgUIAU`) since 0.2.0; install orgs need this version or newer |

## Build a beta version
**Follow `reference/BUILD_RUNBOOK.md`**: the build runs in a snapshot (`config/build-def.json`) that must have CQ 15.6.0.3, Einstein generative AI and Agentforce, and the runbook checks each step first.

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
- Permission sets for every user: `enablement__Doc_From_PDF_Agent_Access` (from the package) **and** the standard **Prompt Template User**, plus their usual CQ permissions and membership of the Draft and Release libraries.
- Prompt template `Doc_PDF_Field_Suggestions` (Prompt Builder; text in `reference/Doc_PDF_Field_Suggestions_prompt.txt`).
- List button (0.3 and later): Setup > Object Manager > Controlled Document > List View Button Layout > Edit, add **Create from File**. It opens the Controlled Document Agent with "Create a controlled document from a file" (Lightning desktop only).
- The agent itself: paste `Controlled_Document_Agent_Script.txt` in Agent Builder. In a packaged org, the three `complex_data_type_name` values use the `enablement__` prefix instead of `c__`.
- Released TMP templates (TMP-POL-000, TMP-PROC-000, TMP-WI-000) with status Current.
