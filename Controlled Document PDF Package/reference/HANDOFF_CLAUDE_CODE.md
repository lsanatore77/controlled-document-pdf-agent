# Handing the 0.3.0 build to Claude Code (Lou's checklist)

Claude Code runs on your computer with your Salesforce CLI logins and follows `CLAUDE.md` and
`reference/BUILD_RUNBOOK.md` in this folder. It makes the 15.6 snapshot and builds 0.3.0, then stops.
It will **not** promote or upgrade any org; you do those later.

You need to be there for about **30 minutes at the start**. After that it can run alone for 3–4 hours.

## Before you start (about 15 minutes)

1. **Fresh copy of the code.** Download the latest `screen-flow` ZIP from GitHub
   (lsanatore77/controlled-document-pdf-agent) and extract it to a **new** folder outside OneDrive, for example:
   ```
   mkdir "C:\Users\LouSanatore\Projects\PDF 0.3.0 run"
   tar -xf "<downloaded zip>" -C "C:\Users\LouSanatore\Projects\PDF 0.3.0 run"
   ```
   Check that `Controlled Document PDF Package` has `CLAUDE.md` and a `.claude` folder (it may be hidden;
   in File Explorer turn on View > Show > Hidden items).

2. **The six CQ zips.** From Confluence, KB page *Minor Release - Winter 25*, download these into
   `C:\Users\LouSanatore\Projects\CQ156zips`:
   - `extPkg_CQWinter25_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQDocument_Extensions_Fresh_Installation.zip`
   - `extPkg_CQWinter25_User_Interface.zip`
   - `extPkg_CQWinter25_CQApproval_Extension_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQPlatformEventSubscriberConfigs_Fresh_Installation.zip`
   - `extPkg_CQWinter25_CQForms_Extension_Fresh_Installation.zip`

3. **Keep the computer awake.** Windows Settings > System > Power > Screen and sleep: set **sleep when
   plugged in** to **Never**. Keep it plugged in. If it sleeps, Claude Code pauses.

4. **CLI logins still work.** In a terminal:
   ```
   sf org display --target-org golden
   sf org display --target-org master
   ```
   Both should show **Connected**. If one says expired, log in again (`sf org login web --alias golden --set-default-dev-hub`)
   before starting. Claude Code can't log in for you.

## Start Claude Code (about 5 minutes)

5. In VS Code: **File > Open Folder** and open exactly
   `...\PDF 0.3.0 run\controlled-document-pdf-agent-screen-flow\Controlled Document PDF Package`
   (this folder, so Claude Code reads `CLAUDE.md` and the pre-approved commands in `.claude/settings.json`).

6. Open Claude Code. If it asks whether you trust this folder, choose **Yes** (otherwise it ignores
   `.claude/settings.json`). Then type `/permissions`. The **Allow** list should show the `sf ...` commands.
   If it doesn't, note it; you'll approve them in step 9 instead.

   Then type `/add-dir C:\Users\LouSanatore\Projects\CQ156zips` so Claude Code can unzip and edit files
   in the zip folder without asking. `/permissions` should then list **2** workspace directories.

7. Press **Shift+Tab** until it shows **accept edits on**, so it can edit the two config files without asking.

8. Paste this prompt:

   > Read CLAUDE.md and reference/BUILD_RUNBOOK.md. Do runbook section A (A0 to A5) and then section B
   > (build), following every rule in CLAUDE.md. The six CQ zips are in C:\Users\LouSanatore\Projects\CQ156zips.
   > When the scratch org from A1 is ready, stop and tell me so I can do the A1 clicks. Never promote,
   > never upgrade or change any org except the scratch org CQ156AI. If anything fails, stop and write
   > the summary to reference/BUILD_LOG.md.

## Stay for the first part (about 20 minutes)

9. **Answer any permission prompt** with **Yes, and don't ask again**. Every kind of command should come
   up once while you're there (org list, display, create scratch, resume, package install, report...).

10. When it says the scratch org **CQ156AI** is ready, open it (`sf org open --target-org CQ156AI`) and do
    the A1 clicks from the CQ 15.6 install guide (*IQ for CQ Winter 2025 - Fresh Installation*):
    - Setup > Process Automation Settings > **Default Workflow User** = the scratch org's admin user > Save.
    - Glance down the guide's prerequisite list (Notes, Digital Experiences, Enhanced Email, custom address
      fields, Translation Workbench, Chatter, CRM Content...). Switch on anything that's off.
    - Pre-installation record types: Account **Default**, Event **Standard**, Task **Standard Task**, and set
      them on the **New Event** and **New Task** global actions.

    Then tell Claude Code: **"A1 clicks done, continue."**

11. **Wait until the first zip has been unzipped and deployed, and one status check (with a `sleep`) has
    run without a prompt.** That covers every kind of command. Then it's safe to leave.
    Leave VS Code open. If your Claude plan hits a usage limit mid-run, Claude Code pauses; the progress
    lines in `reference/BUILD_LOG.md` show where to resume.

## When you're back

12. Open `reference/BUILD_LOG.md` (or read Claude Code's last message) and paste it into the chat with
    Claude in the claude.ai app. We'll check the results together, then promote and upgrade.

If Claude Code stopped early, that's by design: it stops instead of guessing. Bring the summary and
we'll fix the cause before running again.
