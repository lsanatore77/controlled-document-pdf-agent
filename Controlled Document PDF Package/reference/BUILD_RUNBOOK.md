# Building and releasing a package version (enablement)

How to build, promote and roll out a new version of **Enablement - Document Agent**, with a check
before every long step. Run every command from the **Controlled Document PDF Package** folder,
outside OneDrive. Nothing here deploys code to golden or master: golden is only the Dev Hub.

## What the package needs in its build org

Checked from the code (Nov 2026). The build org must have all of these, or the build fails:

| Needs | Why | Comes from |
|---|---|---|
| ComplianceQuest **15.6.0.3** (core) | The package depends on it (`04tKg000000xAgUIAU`) | Installed in the build snapshot |
| Custom Address fields + State and Country/Territory picklists | CQ won't install without them | Build snapshot |
| **Einstein generative AI** (Prompt Builder) | `DocPdfAiSuggestions` and `DocPdfCompareService` use `ConnectApi.EinsteinLLM` | Build snapshot |
| **Agentforce** | Agent input/output components, Lightning types, the list button's `lightning/accApi` | Build snapshot |

The Google Vision Named Credential is only used at run time (`callout:` text), so the build doesn't need it.

## How the build finds its org

- `sfdx-project.json` → `"definitionFile": "config/build-def.json"`
- `config/build-def.json` → `"snapshot": "<snapshot name>"`

Always keep both. Without them, Salesforce's default build org can't install CQ (Address fields error, Nov 2026).

## A. Make the build snapshot (once, then about every 80 days)

Snapshots expire 90 days after they're created and can't be extended or copied.

The scratch org starts from **golden's org shape** (`sourceOrg`), which brings everything CQ's install
guide needs (Notes, Digital Experiences, Enhanced Email, custom address fields, Translation Workbench,
Chatter, CRM Content, ...). Org shape doesn't bring Einstein generative AI, so
`config/cq156-ai-scratch-def.json` adds it and Agentforce on top. Don't replace the shape with a plain
definition: CQ won't install without those settings.

0. **Checks before you start** (1 minute)
   ```
   sf org list shape --target-dev-hub golden
   sf org display --target-org golden
   ```
   ✔ golden's shape shows **Active**.
   ✔ In `config/cq156-ai-scratch-def.json`, `sourceOrg` is golden's org Id (the `Id` from `sf org display`,
   starting `00D`). Use the same value as in your `golden-shape-def.json`, which worked on Nov 8.
   It must not say `PASTE_GOLDEN_ORG_ID_HERE`.

1. **Scratch org from golden's shape, plus Einstein and Agentforce** (about 5 minutes)
   ```
   sf org create scratch --definition-file config/cq156-ai-scratch-def.json --alias CQ156AI --no-namespace --duration-days 7 --target-dev-hub golden --wait 30
   ```
   ✔ Ends with "Your scratch org is ready".
   ✘ If it fails on `Einstein1AIPlatform` or an AI setting: stop and paste the error. Don't remove them
   and carry on: the package needs them.

2. **Install CQ 15.6.0.3** (about 15–30 minutes)
   ```
   sf package install --package 04tKg000000xAgUIAU --target-org CQ156AI --security-type AdminsOnly --no-prompt --wait 30
   sf package installed list --target-org CQ156AI
   ```
   ✔ ComplianceQuest 15.6.0.3 is listed.
   If the install command stops waiting before it finishes, it keeps running in the org. Check it with the
   request Id it printed (`0Hf...`) instead of installing again:
   ```
   sf package install report --request-id 0Hf... --target-org CQ156AI
   ```

3. **Dry run: does the whole package compile and pass its tests here?** (about 5–15 minutes)
   ```
   sf project deploy start --source-dir force-app --target-org CQ156AI --dry-run --test-level RunLocalTests --wait 30
   ```
   ✔ "Succeeded" (nothing is saved, it only checks). **Don't go on unless this passes**: it tests
   the same things the package build will.

4. **Snapshot it** (a few minutes to an hour)
   ```
   sf org create snapshot --source-org CQ156AI --name CQ156AISnap --target-dev-hub golden --description "CQ 15.6.0.3 core, Einstein GenAI, Agentforce"
   sf org list snapshot --target-dev-hub golden
   ```
   ✔ CQ156AISnap shows **Active**. Note its expiration date.

5. **Point the build at it**: in `config/build-def.json`, set `"snapshot": "CQ156AISnap"`. Save.

When renewing, give the new snapshot a new name (for example `CQ156AISnap0227`), switch
`build-def.json` to it only after it's Active, then delete the old one.

## B. Build the version (20–40 minutes)

Check first:
```
sf org list snapshot --target-dev-hub golden
```
✔ The snapshot named in `build-def.json` is **Active**.

Build:
```
sf package version create --package "Enablement - Document Agent" --installation-key-bypass --code-coverage --wait 60 --target-dev-hub golden
```
Right after it starts, check it's running:
```
sf package version create list --target-dev-hub golden --created-last-days 1
```
✔ "Successfully created the package version" with a new **04t** Id. Keep it.

If it fails: read the **first** error. Later errors ("Dependent class is invalid", "can't find the action")
usually follow from it. Find the cause before building again.

## C. Promote it (permanent: can't be undone)

Check first:
```
sf package version report --package 04t... --target-dev-hub golden
```
✔ **Has Passed Code Coverage Check: true** (75% or more), and the version number is the one you meant to build.

Promote:
```
sf package version promote --package 04t... --no-prompt --target-dev-hub golden
```
✔ "Successfully promoted". Production orgs only take promoted versions.

## D. Upgrade each org (one at a time)

Order: **golden first** (test the list button there), then master and basfplay.

Before each org:
```
sf package installed list --target-org <org>
sf data query --query "SELECT Id, DeveloperName FROM BotDefinition WHERE DeveloperName = 'Controlled_Document_Agent'" --target-org <org>
```
✔ ComplianceQuest is 15.6.0.3 or later; note the current Enablement - Document Agent version.
✔ One agent row comes back. The list button finds the agent by this API name; if the org's agent has a
different API name, the button says the agent wasn't found.

Upgrade:
```
sf package install --package 04t... --target-org <org> --wait 30 --no-prompt
sf package installed list --target-org <org>
```
✔ The new version is listed.

After each upgrade (0.3 and later):
- Setup > Object Manager > Controlled Document > **List View Button Layout** > Edit > add **Create from File** > Save.
- Test: Controlled Documents list view in Document Control > **Create from File**: the agent opens with the upload box.

## Snapshot calendar (as of Nov 25, 2026)

| Snapshot | Use | Expires |
|---|---|---|
| CQ16BaseSnap | CQ 16.0 fuller install: Atlas seed, dev | 2027-01-28 |
| CQ156BaseSnap | CQ 15.6 core, **no Einstein**: not enough for package builds | 2027-02-06 |
| CQ16AISnap | CQ 16 with AI (made in another chat) | 2027-02-19 |
| CQ156AISnap | Package builds (to be created) | 90 days after creation |
