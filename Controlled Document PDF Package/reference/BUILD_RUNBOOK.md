# Building and releasing a package version (enablement)

> **Nov 25, 2026: build from golden's org shape, not a snapshot.** Salesforce doesn't allow managed
> package versions built from a snapshot to be promoted. `config/build-def.json` now uses golden's shape
> (`sourceOrg`) plus Einstein and Agentforce, the same recipe that installed CQ and compiled the code in
> CQ156AI. Section A (snapshot) is kept only for making CQ 15.6 dev/test orgs.

> **Running this with Claude Code?** Start with `reference/HANDOFF_CLAUDE_CODE.md`. Claude Code also reads
> `CLAUDE.md`, which replaces this runbook's long `--wait` values with short waits plus status checks
> (its commands stop after about 10 minutes).

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

## A. Make the 15.6 build snapshot (once, then about every 80 days)

Snapshots expire 90 days after they're created and can't be extended or copied. This snapshot mirrors
**CQ16BaseSnap** (golden's shape + six CQ packages + CQ's external zips), but on CQ 15.6, plus Einstein
generative AI and Agentforce, which the package needs. Allow 2–3 hours, mostly waiting.

Source documents (Confluence, ComplianceQuest space):
- *IQ for CQ Winter 2025 - Fresh Installation* (this is the CQ 15.6 install)
- *IQ for CQ Forms Extension Winter 2025 - Fresh Installation*
- Zips: KB page *Minor Release - Winter 25* (CQ Release Notes & Installation Portal)

### A0. Checks and downloads before you start (10 minutes)

0. **golden has room** (Developer Edition Dev Hub: 3 active scratch orgs, 5 active snapshots,
   6 package builds per 24 hours)
   ```
   sf limits api display --target-org golden
   ```
   ✔ Remaining: **ActiveScratchOrgs** ≥ 1, **DailyScratchOrgs** ≥ 1, **ActiveOrgSnapshots** ≥ 1,
   **Package2VersionCreates** ≥ 1. If not, Lou deletes an old scratch org or snapshot first.

1. **golden's shape is Active, and golden's org Id**
   ```
   sf org list shape
   sf org display --target-org golden
   ```
   ✔ Shape **Active**. Put golden's org Id (`00D...`) in `sourceOrg` in `config/cq156-ai-scratch-def.json`
   (same value as your `golden-shape-def.json`). It must not say `PASTE_GOLDEN_ORG_ID_HERE`.

2. **Exact package versions: copy them from master**, so the snapshot matches master
   ```
   sf package installed list --target-org master
   ```
   Write down the **04t** and version of each of these six. Use master's 04t in step A2, not the guide's:

   | Package | Install guide's 04t (15.6.0 fresh) | Use |
   |---|---|---|
   | ComplianceQuest | `04tRn000000kkcXIAQ` (15.6.0) | **master's**. Must be `04tKg000000xAgUIAU` or a later 15.6.x, or the build fails its dependency |
   | CQ Document Extensions App | `04tRn000000klC1IAI` (15.6.0) | master's |
   | ComplianceQuest User Interface | `04tRn000000kV2PIAU` (15.5.0) | master's |
   | CQ Approval Extension | `04tRn000000kV8rIAE` (15.5.0) | master's |
   | CQ Forms Extension | `04tRn000000kVK9IAM` (15.5.0) | master's |
   | Salesforce Mobile Apps | `04t4V000001i8c0QAA` (1.24) | master's |

   ✘ If master's ComplianceQuest is *older* than `04tKg000000xAgUIAU` or missing: stop and ask.

3. **Download the six fresh-install zips** from *Minor Release - Winter 25* into one short folder outside
   OneDrive (for example `C:\Users\LouSanatore\Projects\CQ156zips`). Shorten names if unzipping fails.
   - `extPkg_CQWinter25_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQDocument_Extensions_Fresh_Installation.zip`
   - `extPkg_CQWinter25_User_Interface.zip`
   - `extPkg_CQWinter25_CQApproval_Extension_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQPlatformEventSubscriberConfigs_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQForms_Extension_Fresh_Installation.zip`

   Use the **Fresh_Installation** zips only, not the `Upgrade_From_...` ones.

### A1. Scratch org from golden's shape, plus Einstein and Agentforce (about 5 minutes)

```
sf org create scratch --definition-file config/cq156-ai-scratch-def.json --alias CQ156AI --no-namespace --duration-days 14 --target-dev-hub golden --wait 30
```
✔ "Your scratch org is ready".
✘ If it fails on `Einstein1AIPlatform` or an AI setting: stop and paste the error. Don't remove them.

Then, in the org (`sf org open --target-org CQ156AI`), set the two things the zips need:
- Setup > **Process Automation Settings** > **Default Workflow User** = the scratch org's admin user. Save.
- The prerequisite list at the top of the install guide (Notes, Digital Experiences, Enhanced Email,
  custom address fields, Translation Workbench, Chatter, CRM Content, ...): golden's shape normally
  brings these. Glance down the list and switch on anything that's off.
- The guide's pre-installation record types (Account "Default", Event "Standard", Task "Standard Task",
  and New Event / New Task global actions), as you did for 16.0.

### A2. Install the packages and zips, in the guide's order

Install each package with master's 04t from A0.2, then check it's listed before the next one:
```
sf package install --package 04t... --target-org CQ156AI --security-type AdminsOnly --no-prompt --wait 60
sf package installed list --target-org CQ156AI
```
If the command stops waiting before the install finishes, it keeps running in the org. Check with the
request Id it printed instead of installing again:
```
sf package install report --request-id 0Hf... --target-org CQ156AI
```

Deploy each zip the same way:
1. Unzip it into a new empty folder (Windows: right-click > Extract All, or
   `powershell -NoProfile -Command Expand-Archive -LiteralPath '<zip>' -DestinationPath '<new folder>'`),
   and find the folder that has `package.xml` directly inside it. CQ's zips usually have one top folder (for example `...Src`) holding `package.xml`.
2. Deploy **that folder**, with the test the guide specifies:
   ```
   sf project deploy start --metadata-dir "<folder that contains package.xml>" --target-org CQ156AI --test-level RunSpecifiedTests --tests compliancequest.SQX_Test_1931_ContentVersionPerm --wait 60
   ```
✔ "Succeeded" for each. Deploying the unzipped folder avoids guessing how each zip is laid out.

| # | Install / deploy | Check |
|---|---|---|
| 1 | ComplianceQuest (core) | Listed, same version as master |
| 2 | `extPkg_CQWinter25_Fresh_Installation.zip` | Succeeded. "Permission Set Groups is updating": wait 5 minutes and run it again; if it keeps failing, split it as for 16.0 (`1a` without groups, `1b` groups only) |
| 3 | CQ Document Extensions App | Listed |
| 4 | `extPkg_CQWinter25_CQDocument_Extensions_Fresh_Installation.zip` | Succeeded |
| 5 | ComplianceQuest User Interface | Listed |
| 6 | `extPkg_CQWinter25_User_Interface.zip` | Succeeded |
| 7 | CQ Approval Extension | Listed |
| 8 | `extPkg_CQWinter25_CQApproval_Extension_Fresh_Installation.zip` | Succeeded |
| 9 | `extPkg_CQWinter25_CQPlatformEventSubscriberConfigs_Fresh_Installation.zip` | After unzipping, **before** deploying: in every file in the `PlatformEventSubscriberConfigs` folder, replace `<user>cqsupport@compliancequest.com</user>` with `<user>` + the scratch org's admin username (the Default Workflow User; `sf org display --target-org CQ156AI` shows it) + `</user>`. VS Code's Replace in Files (Ctrl+Shift+H) does it in one go. Then deploy the folder. Succeeded |
| 10 | Salesforce Mobile Apps | Listed |
| 11 | CQ Forms Extension | Listed |
| 12 | `extPkg_CQWinter25_CQForms_Extension_Fresh_Installation.zip` | Succeeded |

Then confirm all six are there:
```
sf package installed list --target-org CQ156AI
```
✔ The same six packages and versions as master.

### A3. Dry run: does the whole Document Agent package compile and pass its tests here? (5–15 minutes)

```
sf project deploy start --source-dir force-app --target-org CQ156AI --dry-run --test-level RunLocalTests --wait 30
```
✔ "Succeeded" (nothing is saved, it only checks). **Don't snapshot unless this passes**: it tests the
same things the package build will (CQ, Einstein generative AI, Agentforce, our code and tests).

### A4. Snapshot it (a few minutes to an hour)

```
sf org create snapshot --source-org CQ156AI --name CQ156AISnap --target-dev-hub golden --description "CQ 15.6 as master (6 packages + zips), Einstein GenAI, Agentforce"
sf org list snapshot --target-dev-hub golden
```
✔ CQ156AISnap shows **Active**. Note its expiration date.

### A5. Point the build at it

In `config/build-def.json`, set `"snapshot": "CQ156AISnap"`. Save.

When renewing, give the new snapshot a new name (for example `CQ156AISnap0227`), switch `build-def.json`
to it only after it's Active, then delete the old one.

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
sf package version report --package 04t... --target-dev-hub golden --verbose
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
| ~~CQ156BaseSnap~~ | Deleted Nov 25, 2026 (no Einstein, couldn't build the package) | - |
| CQ16AISnap | CQ 16 with AI (made in another chat) | 2027-02-19 |
| CQ156AISnap | Package builds (to be created) | 90 days after creation |
