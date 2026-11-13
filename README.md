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

**GitHub Actions is the only automatic system.** It runs in the cloud every weekday at 3:45 PM EST — even when Tori is out of office or her computer is off.
- Workflow file: `.github/workflows/refresh.yml` in the GitHub repo
- Script file: `refresh.ps1` in the GitHub repo (cloud version — reads ADO token from GitHub secret)
- Anyone on the team can trigger a manual run from: **github.com/toriladen/ds-release-notes/actions**
- Run history and logs are visible to the whole team on that same Actions page
- Uses an ADO API token stored securely as a GitHub secret named `ADO_PAT`

### Previously there were two other systems — now disabled
A Windows Task Scheduler job on Tori's computer and a Claude scheduled task used to run the same refresh at the same time of day as a "backup." In practice all three raced to push to the same branch at once, which caused rejected pushes and merge conflicts on several days in November 2026. Both backups were disabled on 2026-11-13 so GitHub Actions is the single source of truth:
- **Windows Task Scheduler** — task `DS Release Notes Refresh` (path `\MSI\`), state set to Disabled. The script `Refresh-ReleaseNotes.ps1` and its log `Refresh-ReleaseNotes.log` (both in the CLAUDE folder) still exist but no longer run on a schedule.
- **Claude scheduled task** — `ds-release-notes-refresh`, set to `enabled: false` in the Claude desktop app's Scheduled section. The task definition still exists and can be manually run or re-enabled if ever needed.

If GitHub Actions itself needs a backup again, re-enable only one of these — never both at once — to avoid the same race.

---

## What happens after the script runs?

1. The script builds a fresh HTML file and saves it locally
2. It pushes the file to GitHub: **github.com/toriladen/ds-release-notes**
3. Netlify (a free web hosting service connected to that GitHub repo) automatically detects the push and redeploys the site within about 30 seconds
4. At 4:00 PM ET, the page auto-reloads in any browser that has it open, picking up the fresh content

---

## What if the page looks outdated?

**Step 1 — Check the GitHub Actions run history**
Go to **github.com/toriladen/ds-release-notes/actions** and look at the most recent run. It'll show whether the refresh succeeded or failed, with full logs.

**Step 2 — Run it manually**
Trigger GitHub Actions from the browser (works for anyone on the team, no computer required):
1. Go to **github.com/toriladen/ds-release-notes/actions**
2. Click **"Refresh Release Notes"** in the left sidebar
3. Click **"Run workflow"** → **"Run workflow"**

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
| Local script (disabled) | `CLAUDE\Refresh-ReleaseNotes.ps1` |
| Local run log (disabled) | `CLAUDE\Refresh-ReleaseNotes.log` |
| HTML source copy | `CLAUDE\release-notes.html` |
| GitHub repo folder | `CLAUDE\ds-release-notes\index.html` |
| Live website | https://dsreleasenotes.netlify.app |
| GitHub repo | https://github.com/toriladen/ds-release-notes |

---

## Who to contact if something breaks

- **Page not updating** → Check the GitHub Actions run history, or ask Claude to run it manually
- **ADO token expired** → Generate a new PAT at dev.azure.com (see Step 3 above)
- **GitHub push failing** → The GitHub token may need to be refreshed — ask Claude for help
- **Netlify down** → Check netlify.com status; this is rare and usually resolves on its own

---

*Last updated: 2026-11-13*
