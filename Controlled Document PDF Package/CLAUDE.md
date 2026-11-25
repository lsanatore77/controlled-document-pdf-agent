# Instructions for Claude Code: Enablement - Document Agent (managed package)

You are helping Lou build version **0.3.0** of the managed package **Enablement - Document Agent**
(namespace `enablement`, package Id `0Hofn0000001ZTZCA2`, Dev Hub alias `golden`).
Lou may be away. Work carefully, one step at a time, and stop rather than improvise.

## Your job

Follow `reference/BUILD_RUNBOOK.md`:
- **Section A** (A0 to A5): make the CQ 15.6 build snapshot `CQ156AISnap`.
- **Section B**: build the 0.3.0 package version.

**Do not do section C (promote) or section D (upgrade orgs).** Promote is permanent and upgrades touch
real orgs; Lou does those with you later.

## Hard rules

1. **Never deploy to, install into, or change `golden`, `master`, `basfplay`, `dev` or any org other
   than the scratch org `CQ156AI`.** golden is only used as `--target-dev-hub` (creating the scratch org,
   the snapshot and the package version). Read-only commands on master (`sf package installed list`) are fine.
2. **Never run `sf package version promote`.**
3. **Check every step's ✔ result before the next step.** If a step fails, try the fix the runbook gives
   (if any) **once**. If it still fails, or the runbook has no fix, **stop** and write the summary below.
4. **Don't change the package's code** (`force-app/`) or `sfdx-project.json`. The only files you may
   edit are `config/cq156-ai-scratch-def.json` (golden's org Id, step A0), `config/build-def.json`
   (snapshot name, step A5) and the unzipped CQ Platform Event files (username, step A2 row 9).
5. **Don't install anything twice.** If an install stops waiting, check it with
   `sf package install report --request-id 0Hf... --target-org CQ156AI`.
6. **Use the package versions from master** (`sf package installed list --target-org master`), not the
   install guide's, as the runbook says (A0.2). If master's ComplianceQuest is older than
   `04tKg000000xAgUIAU`, stop.
7. Pass `--target-org` / `--target-dev-hub` explicitly on every command. Don't rely on defaults.
8. **Run the package build (section B) only once.** golden allows 6 package version builds per 24 hours
   (`Package2VersionCreates` in `sf limits api display --target-org golden`). If the build fails, stop and
   write the summary; don't build again.

## Long-running commands (important)

Your shell commands time out after about 10 minutes, but CQ installs, zip deploys with tests, the
snapshot and the package build can each take 15–60 minutes. They keep running in Salesforce after your
command stops waiting, so **a timeout is not a failure**. Never repeat a long command because it timed
out; check its status instead. Start long steps with a short wait and then poll:

| Step | Start with | Then check every ~5 minutes with |
|---|---|---|
| Scratch org | `sf org create scratch ... --wait 8` | `sf org resume scratch --job-id <id it printed> --wait 8` |
| Package install | `sf package install ... --wait 8` | `sf package install report --request-id 0Hf... --target-org CQ156AI` (until Status: SUCCESS) |
| Zip deploy | `sf project deploy start ... --wait 8` | `sf project deploy report --job-id 0Af... --target-org CQ156AI` (until Succeeded) |
| Dry run (A3) | `sf project deploy start ... --dry-run --wait 8` | `sf project deploy report --job-id 0Af... --target-org CQ156AI` |
| Snapshot | `sf org create snapshot ...` (returns at once) | `sf org list snapshot --target-dev-hub golden` (until Active) |
| Package build (B) | `sf package version create ... --wait 8` | `sf package version create report --package-create-request-id 08c... --target-dev-hub golden` (until Success or Error) |

Between checks, wait with `sleep 240` (set the command timeout to 600000 ms). If a foreground `sleep` is
refused, use your background/monitor wait instead; never skip the wait and re-run the long command.
Always keep the Id each command prints.

Run **one command per call**: no `&&`, `;` or pipes, and no `cd` in front. The pre-approved commands in
`.claude/settings.json` only match a plain command, so a chained one stops and waits for Lou's approval.

Make file edits (golden's org Id, the snapshot name, the Platform Event usernames) with your file-editing
tool, not with shell scripts.

## Unzipping the CQ zips (Windows)

This is a Windows computer. In Git Bash, `tar` may be GNU tar, which can't open `.zip` files. Use:
```
powershell -NoProfile -Command Expand-Archive -LiteralPath 'C:\Users\LouSanatore\Projects\CQ156zips\<zip>' -DestinationPath 'C:\Users\LouSanatore\Projects\CQ156zips\u1'
```
with a new short folder for each zip (`u1`, `u2`, ...). If a path is too long, stop and tell Lou.
Then find the folder that directly contains `package.xml` and deploy that folder.

## Progress log

After **each** completed step (A0.1, A0.2, A1, each A2 row, A3, A4, A5, B), append one line to
`reference/BUILD_LOG.md`: time, step, result, and any Id (04t, 0Hf, 0Af, 08c). If the session stops
unexpectedly, this is how Lou and Claude know where to resume.

## Inputs Lou provides before leaving

- The six CQ Winter 25 fresh-install zips, in a folder Lou tells you (default
  `C:\Users\LouSanatore\Projects\CQ156zips`). Lou downloads them from Confluence; you can't.
- Step A1's clicks in the new scratch org (Default Workflow User, prerequisite check, record types).
  When the scratch org is created, **stop and tell Lou** it's ready for those clicks, unless Lou has
  already said they're done. Continue with A2 only after Lou confirms.

## When you stop or finish

Append a summary to `reference/BUILD_LOG.md` (create it if missing), then say the same in chat:
- Date and time, the last step completed (for example "A2 row 6"), and the next step.
- For each package installed: name, version, 04t.
- The snapshot name and its status/expiry, if created.
- The 0.3.0 package version 04t and its code coverage, if built.
- If something failed: the exact command, the **first** error message in full, and what you tried.

## Background (why it's set up this way)

- Salesforce's default package build org can no longer install CQ (custom Address fields error), so the
  build runs in a snapshot (`config/build-def.json` → `"snapshot"`). Keep `definitionFile` in
  `sfdx-project.json`.
- The old snapshot `CQ156BaseSnap` (CQ core only) lacks Einstein generative AI, so `DocPdfAiSuggestions`
  and `DocPdfCompareService` (`ConnectApi.EinsteinLLM`) don't compile there. That's why `CQ156AISnap`
  is made from golden's org shape **plus** Einstein and Agentforce (`config/cq156-ai-scratch-def.json`).
- The package depends on ComplianceQuest 15.6.0.3 (`04tKg000000xAgUIAU`) or later, so master (CQ 15.6)
  can install it.
