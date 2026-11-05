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

There are **three automatic systems** that refresh the page every weekday at 3:45 PM Eastern. GitHub Actions is the primary — it runs in the cloud and doesn't require anyone's computer to be on.

### System 1 — GitHub Actions (primary, cloud-based)
A workflow runs automatically in the cloud every weekday at 3:45 PM EST — even when Tori is out of office.
- Workflow file: `.github/workflows/refresh.yml` in the GitHub repo
- Script file: `refresh.ps1` in the GitHub repo (cloud version — reads ADO token from GitHub secret)
- Anyone on the team can trigger a manual run from: **github.com/toriladen/ds-release-notes/actions**
- Run history and logs are visible to the whole team on that same Actions page
- Uses an ADO API token stored securely as a GitHub secret named `ADO_PAT`

### System 2 — Windows Task Scheduler (local backup)
A PowerShell script runs directly on Tori's computer every weekday at 3:45 PM.
- Script file: `Refresh-ReleaseNotes.ps1` (in the CLAUDE folder)
- Log file: `Refresh-ReleaseNotes.log` (same folder — check this if something looks wrong)
- Requires Tori's computer to be on and connected to the internet

### System 3 — Claude Scheduled Task (secondary backup)
A Claude AI routine also runs every weekday at 3:45 PM.
- Visible in the Claude desktop app under the "Scheduled" section in the sidebar
- Requires the Claude desktop app to be open to run

If GitHub Actions fails, the local script should catch it. All three do the same thing.

---

## What happens after the script runs?

1. The script builds a fresh HTML file and saves it locally
2. It pushes the file to GitHub: **github.com/toriladen/ds-release-notes**
3. Netlify (a free web hosting service connected to that GitHub repo) automatically detects the push and redeploys the site within about 30 seconds
4. At 4:00 PM ET, the page auto-reloads in any browser that has it open, picking up the fresh content

---

## What if the page looks outdated?

**Step 1 — Check the log file**
Open `Refresh-ReleaseNotes.log` in the CLAUDE folder. The last few lines will tell you whether the script ran successfully or hit an error.

**Step 2 — Run it manually**
Easiest option — trigger GitHub Actions from the browser (works for anyone on the team, no computer required):
1. Go to **github.com/toriladen/ds-release-notes/actions**
2. Click **"Refresh Release Notes"** in the left sidebar
3. Click **"Run workflow"** → **"Run workflow"**

Or run locally on Tori's computer via PowerShell:
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
| Local script | `CLAUDE\Refresh-ReleaseNotes.ps1` |
| Local run log | `CLAUDE\Refresh-ReleaseNotes.log` |
| HTML source copy | `CLAUDE\release-notes.html` |
| GitHub repo folder | `CLAUDE\ds-release-notes\index.html` |
| Live website | https://dsreleasenotes.netlify.app |
| GitHub repo | https://github.com/toriladen/ds-release-notes |

---

## Who to contact if something breaks

- **Page not updating** → Check the log file, or ask Claude to run it manually
- **ADO token expired** → Generate a new PAT at dev.azure.com (see Step 3 above)
- **GitHub push failing** → The GitHub token may need to be refreshed — ask Claude for help
- **Netlify down** → Check netlify.com status; this is rare and usually resolves on its own

---

*Last updated: November 2026*
