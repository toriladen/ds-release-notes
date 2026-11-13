# Data Services Release Notes — How It Works

## What is this?

The Data Services Release Notes page is a website that automatically shows two things:
- **What got deployed this week** — work items closed in the last 7 days that are marked as Deployed in Azure DevOps
- **What's coming in the next release** — work items that are ready and queued up but not yet deployed

The page lives at: **https://dsreleasenotes.netlify.app**
It is also embedded in SharePoint so the team can see it without leaving that page.

---

## Where does the data come from?

All data comes from **Azure DevOps (ADO)** — the same system the team uses to track work items, bugs, and features. Two saved queries pull the data automatically:

1. **Deployed this week** — finds any item closed in the last 7 days where the Production Status field is set to "Deployed"
2. **Coming in next release** — runs a saved ADO query (ID: `83721bdb`) that the team maintains

No one has to manually update the page. It stays current on its own.

---

## How does the page get updated?

**GitHub Actions is the primary system**, with a Windows Task Scheduler job as an automatic fallback. They're sequenced 30 minutes apart and the fallback checks GitHub's own run history before doing anything, so they don't race each other.

### Primary — GitHub Actions (cloud-based)
A workflow runs automatically in the cloud every weekday at 3:45 PM EST — even when Tori is out of office or her computer is off.
- Workflow file: `.github/workflows/refresh.yml` in the GitHub repo
- Script file: `refresh.ps1` in the GitHub repo (cloud version — reads ADO token from GitHub secret)
- Anyone on the team can trigger a manual run from: **github.com/toriladen/ds-release-notes/actions**
- Run history and logs are visible to the whole team on that same Actions page
- Uses an ADO API token stored securely as a GitHub secret named `ADO_PAT`

### Fallback — Windows Task Scheduler (local, conditional)
Task `DS Release Notes Refresh` (path `\MSI\`) runs `Refresh-ReleaseNotes.ps1` on Tori's computer every weekday at **4:15 PM ET — 30 minutes after** GitHub Actions' scheduled run. It is **not** a second unconditional refresh:
1. It first calls the GitHub API to check today's "Refresh Release Notes" Actions run.
2. If that run already **succeeded**, the script logs that and exits immediately — no ADO queries, no commit, no push.
3. Only if today's GitHub Actions run **failed, is still running, or never happened** does it fall back to querying ADO itself, rebuilding `index.html`, and pushing.
4. If GitHub Actions happens to push in the few-second window after the check, the fallback's push does a `git fetch` + merge (preferring its own freshly-generated content) rather than failing outright, so it still gets a copy up.
- Log file: `Refresh-ReleaseNotes.log` (in the CLAUDE folder) — every run logs whether it skipped or executed, and why
- Requires Tori's computer to be on and connected to the internet; if it's off, there's simply no fallback that day

### Disabled — Claude scheduled task
The third system that used to run this (`ds-release-notes-refresh`, a Claude AI routine) is set to `enabled: false` in the Claude desktop app's Scheduled section as of 2026-11-13. Originally all three systems ran unconditionally at the same time and raced to push to the same branch, causing rejected pushes and merge conflicts on several days in November 2026. Rather than add the same GitHub-status check to a third system, it was left disabled — two systems (one primary, one conditional fallback) cover this without a third moving part. It can be manually run or re-enabled if ever needed, but if so, give it its own check-first/offset logic like the Task Scheduler job, not an unconditional run at the same time as the others.

---

## What happens after the script runs?

1. The script builds a fresh HTML file and saves it locally
2. It pushes the file to GitHub: **github.com/toriladen/ds-release-notes**
3. Netlify (a free web hosting service connected to that GitHub repo) automatically detects the push and redeploys the site within about 30 seconds
4. At 4:00 PM ET, the page auto-reloads in any browser that has it open, picking up the fresh content

---

## What if the page looks outdated?

**Step 1 — Check the GitHub Actions run history**
Go to **github.com/toriladen/ds-release-notes/actions** and look at the most recent run. It'll show whether the refresh succeeded or failed, with full logs. If it failed, the 4:15 PM fallback should have caught it automatically — check `Refresh-ReleaseNotes.log` to confirm it ran and pushed.

**Step 2 — Run it manually**
Trigger GitHub Actions from the browser (works for anyone on the team, no computer required):
1. Go to **github.com/toriladen/ds-release-notes/actions**
2. Click **"Refresh Release Notes"** in the left sidebar
3. Click **"Run workflow"** → **"Run workflow"**

Or run the fallback script directly on Tori's computer via PowerShell (it will skip on its own if GitHub Actions already succeeded today):
```
powershell -File "C:\Users\ToriLaden\OneDrive - Millennium Systems International\!Data Services Stuff!\CLAUDE\Refresh-ReleaseNotes.ps1"
```

**Step 3 — If ADO auth fails**
If the log shows an authorization error, the ADO API token may have expired (tokens are set for 1 year). To fix it:
1. Go to dev.azure.com → click your profile picture → Personal Access Tokens
2. Create a new token with "Work Items: Read" permission
3. Open `Refresh-ReleaseNotes.ps1` and replace the token value near the top of the file

---

## Where are all the files?

| What | Where |
|------|-------|
| GitHub Actions workflow | `ds-release-notes\.github\workflows\refresh.yml` |
| Cloud refresh script | `ds-release-notes\refresh.ps1` |
| Actions run history | https://github.com/toriladen/ds-release-notes/actions |
| Local fallback script | `CLAUDE\Refresh-ReleaseNotes.ps1` |
| Local fallback run log | `CLAUDE\Refresh-ReleaseNotes.log` |
| HTML source copy | `CLAUDE\release-notes.html` |
| GitHub repo folder | `CLAUDE\ds-release-notes\index.html` |
| Live website | https://dsreleasenotes.netlify.app |
| GitHub repo | https://github.com/toriladen/ds-release-notes |

---

## Who to contact if something breaks

- **Page not updating** → Check the GitHub Actions run history and `Refresh-ReleaseNotes.log`, or ask Claude to run it manually
- **ADO token expired** → Generate a new PAT at dev.azure.com (see Step 3 above). Note there are two separate ADO tokens to maintain — one in the GitHub secret `ADO_PAT` (for Actions) and one hardcoded near the top of `Refresh-ReleaseNotes.ps1` (for the local fallback)
- **GitHub push failing** → The GitHub token may need to be refreshed — ask Claude for help
- **Netlify down** → Check netlify.com status; this is rare and usually resolves on its own
- **Fallback not catching a failure** → Confirm the Task Scheduler job `DS Release Notes Refresh` (path `\MSI\`) is Enabled and its trigger is still 30 minutes after the GitHub Actions cron in `.github/workflows/refresh.yml`

---

*Last updated: 2026-11-13 (added automatic GitHub Actions → Windows Task Scheduler fallback)*
