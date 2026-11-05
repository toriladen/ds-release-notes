<#
.SYNOPSIS
    Refreshes the Data Services Release Notes page from Azure DevOps.
    Designed to run inside GitHub Actions — reads ADO_PAT from env var,
    writes index.html to the repo root, no git operations (Actions handles that).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── CONFIG ────────────────────────────────────────────────────────────────────
$ADO_PAT          = $env:ADO_PAT
$ADO_ORG          = "millenniumsi"
$ADO_PROJECT      = "MSI"
$NEXT_RELEASE_QID = "83721bdb-e1a6-4a1b-ad04-44d67c66e62a"
$OUT_PATH         = Join-Path $PSScriptRoot "index.html"

$DEPLOYED_WIQL = "SELECT [System.Id] FROM workitems WHERE [System.TeamProject] = 'MSI' AND [Microsoft.VSTS.Common.ClosedDate] >= @today - 7 AND [Custom.ProductionStatus] = 'Deployed' AND [System.AreaPath] UNDER 'MSI\Team Data Troopers'"

if ([string]::IsNullOrWhiteSpace($ADO_PAT)) {
    Write-Error "ADO_PAT environment variable is not set."
    exit 1
}

# ── ADO AUTH ─────────────────────────────────────────────────────────────────
$b64  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$ADO_PAT"))
$hdrs = @{
    Authorization  = "Basic $b64"
    'Content-Type' = 'application/json'
    Accept         = 'application/json'
}

# ── ADO HELPERS ──────────────────────────────────────────────────────────────
function Invoke-Wiql {
    param([string]$wiql)
    $url  = "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/wit/wiql?api-version=7.0"
    $body = ConvertTo-Json @{ query = $wiql } -Depth 2
    $r    = Invoke-RestMethod -Uri $url -Method Post -Headers $hdrs -Body $body
    if ($r.workItems) { return [int[]]($r.workItems | ForEach-Object { $_.id }) }
    return @()
}

function Invoke-SavedQuery {
    param([string]$queryId)
    $url = "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/wit/wiql/${queryId}?api-version=7.0"
    $r   = Invoke-RestMethod -Uri $url -Method Get -Headers $hdrs
    if ($r.workItems) { return [int[]]($r.workItems | ForEach-Object { $_.id }) }
    return @()
}

function Get-WorkItemsBatch {
    param([int[]]$ids)
    if (-not $ids -or $ids.Count -eq 0) { return @() }
    $body = ConvertTo-Json @{
        ids    = $ids
        fields = @(
            'System.Id','System.Title','System.WorkItemType','System.State',
            'System.AreaPath','Microsoft.VSTS.Common.ClosedDate',
            'Microsoft.VSTS.Scheduling.TargetDate','System.Description'
        )
    } -Depth 3
    $url = "https://dev.azure.com/$ADO_ORG/_apis/wit/workitemsbatch?api-version=7.0"
    $r   = Invoke-RestMethod -Uri $url -Method Post -Headers $hdrs -Body $body
    return $r.value
}

# ── TEXT HELPERS ─────────────────────────────────────────────────────────────
function Strip-Html {
    param([string]$html)
    if ([string]::IsNullOrWhiteSpace($html)) { return '' }
    $t = $html -replace '<[^>]+>', ' '
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-Blurb {
    param([string]$description, [string]$title)
    $text = Strip-Html $description
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -lt 20) {
        $clean = $title -replace '^DS:\s*', ''
        return "Updates and improvements related to: $clean."
    }
    if ($text.Length -le 280) { return $text }
    $sub  = $text.Substring(0, 280)
    $dot  = [Math]::Max($sub.LastIndexOf('. '), $sub.LastIndexOf('! '))
    if ($dot -gt 80) { return $sub.Substring(0, $dot + 1) }
    return $sub.TrimEnd() + '...'
}

function Get-AreaShort {
    param([string]$areaPath)
    return ($areaPath -split '\\')[-1]
}

function Get-BadgeInfo {
    param([string]$type)
    switch ($type) {
        'User Story' { return @{ cls='badge-story';   emoji='&#11088;';  label='User Story' } }
        'Bug'        { return @{ cls='badge-bug';     emoji='&#128027;'; label='Bug Fix'    } }
        'Defect'     { return @{ cls='badge-defect';  emoji='&#128295;'; label='Defect'     } }
        'Feature'    { return @{ cls='badge-feature'; emoji='&#128161;'; label='Feature'    } }
        default      { return @{ cls='badge-task';    emoji='&#128203;'; label=$type        } }
    }
}

function Get-TitleEmoji {
    param([string]$title)
    $t = $title.ToLower()
    if ($t -match 'booker')                { return '&#129302;' }
    if ($t -match 'gift.?card')            { return '&#127873;' }
    if ($t -match 'visit.?note')           { return '&#128221;' }
    if ($t -match 'client')                { return '&#128101;' }
    if ($t -match 'employee|staff')        { return '&#128188;' }
    if ($t -match 'appointment')           { return '&#128197;' }
    if ($t -match 'sales|snapshot')        { return '&#128176;' }
    if ($t -match 'sheet|excel|position')  { return '&#128202;' }
    if ($t -match 'case.?sens|file.?name') { return '&#128289;' }
    if ($t -match 'macro')                 { return '&#9881;'   }
    if ($t -match 'error|crash|fail|convert') { return '&#128295;' }
    if ($t -match 'boulevard|vagaro|square|mindbody') { return '&#128260;' }
    return '&#10024;'
}

function Format-Date {
    param([string]$dateStr)
    if ([string]::IsNullOrWhiteSpace($dateStr)) { return '' }
    try { return ([datetime]::Parse($dateStr)).ToString('MMM d, yyyy') } catch { return '' }
}

function Encode-Html {
    param([string]$s)
    return [System.Net.WebUtility]::HtmlEncode($s)
}

# ── CARD BUILDER ─────────────────────────────────────────────────────────────
function Build-Card {
    param($item, [string]$dateEmoji)
    $f      = $item.fields
    $id     = $f.'System.Id'
    $title  = ($f.'System.Title' -replace '^DS:\s*','').Trim()
    $type   = $f.'System.WorkItemType'
    $area   = Get-AreaShort $f.'System.AreaPath'
    $desc   = if ($f.PSObject.Properties['System.Description'])        { [string]$f.'System.Description' }        else { '' }
    $blurb  = Get-Blurb $desc $title
    $badge  = Get-BadgeInfo $type
    $emoji  = Get-TitleEmoji $title
    $closed = if ($f.PSObject.Properties['Microsoft.VSTS.Common.ClosedDate'])      { [string]$f.'Microsoft.VSTS.Common.ClosedDate' }      else { '' }
    $target = if ($f.PSObject.Properties['Microsoft.VSTS.Scheduling.TargetDate'])  { [string]$f.'Microsoft.VSTS.Scheduling.TargetDate' }  else { '' }
    $dateStr  = if ($closed) { Format-Date $closed } elseif ($target) { Format-Date $target } else { '' }
    $dateChip = if ($dateStr) { "$dateEmoji $dateStr" } else { '' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('      <div class="card">')
    [void]$sb.AppendLine('        <div class="card-top">')
    [void]$sb.AppendLine("          <span class=""badge $($badge.cls)"">$($badge.emoji) $($badge.label)</span>")
    [void]$sb.AppendLine("          <span class=""wi-id"">#$id</span>")
    [void]$sb.AppendLine('        </div>')
    [void]$sb.AppendLine("        <div class=""card-title"">$emoji $(Encode-Html $title)</div>")
    [void]$sb.AppendLine("        <div class=""card-blurb"">$(Encode-Html $blurb)</div>")
    [void]$sb.AppendLine('        <div class="card-footer">')
    [void]$sb.AppendLine("          <span class=""area-path"">&#128193; $(Encode-Html $area)</span>")
    [void]$sb.AppendLine("          <span class=""date-chip"">$dateChip</span>")
    [void]$sb.AppendLine('        </div>')
    [void]$sb.AppendLine('      </div>')
    return $sb.ToString()
}

# ── HTML TEMPLATE ─────────────────────────────────────────────────────────────
$HTML_TEMPLATE = @'
<!-- Generated: ##GENERATED_DATE## -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>&#10024; Data Services Release Notes</title>
  <style>
    :root {
      --teal:#204855;--plum:#4B3951;--rust:#A75F37;--sky:#A6C1C9;
      --sand:#D7D6CA;--olive:#9A997B;--lilac:#CCC4CE;
      --bg:#f2f0ec;--surface:#ffffff;--border:#D7D6CA;--text:#1a2e35;--muted:#6b7a82;
      --badge-story:var(--teal);--badge-bug:var(--rust);--badge-defect:#7a4a2a;
      --badge-feature:var(--plum);--badge-task:var(--olive);
    }
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);min-height:100vh}
    header{background:linear-gradient(135deg,var(--teal) 0%,var(--plum) 100%);color:white;padding:2rem 2.5rem 1.75rem;display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:1rem;position:relative;overflow:hidden}
    header::before{content:'';position:absolute;inset:0;background:radial-gradient(ellipse at 10% 80%,rgba(167,95,55,.25) 0%,transparent 55%),radial-gradient(ellipse at 85% 20%,rgba(166,193,201,.18) 0%,transparent 55%);pointer-events:none}
    .header-left{position:relative}
    .header-eyebrow{font-size:.7rem;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--sky);margin-bottom:.35rem}
    header h1{font-size:1.9rem;font-weight:800;letter-spacing:-.02em;line-height:1.1}
    header p.subtitle{font-size:.85rem;color:rgba(255,255,255,.6);margin-top:.35rem}
    .header-meta{text-align:right;font-size:.78rem;color:rgba(255,255,255,.6);line-height:1.8;position:relative}
    .header-meta strong{color:var(--sand)}
    #countdown{color:#f0c97a;font-weight:700}
    main{max-width:1120px;margin:0 auto;padding:2rem 1.5rem}
    .refresh-bar{background:linear-gradient(90deg,rgba(32,72,85,.08),rgba(75,57,81,.06));border:1px solid var(--sky);color:var(--teal);font-size:.78rem;font-weight:500;padding:.55rem 1rem;border-radius:8px;display:flex;align-items:center;gap:.55rem;margin-bottom:2rem}
    section{margin-bottom:3rem}
    .section-header{display:flex;align-items:center;gap:.75rem;margin-bottom:1.25rem;padding-bottom:.75rem;border-bottom:2px solid var(--border)}
    .section-emoji{font-size:1.4rem;line-height:1}
    .section-header h2{font-size:1.15rem;font-weight:800;letter-spacing:-.01em}
    .section-deployed .section-header h2{color:var(--teal)}
    .section-upcoming .section-header h2{color:var(--plum)}
    .section-header .count{background:var(--sand);color:var(--teal);font-size:.72rem;font-weight:700;padding:.2rem .6rem;border-radius:999px;margin-left:.25rem}
    .cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:1rem}
    .card{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:1.3rem 1.45rem;display:flex;flex-direction:column;gap:.65rem;box-shadow:0 2px 6px rgba(32,72,85,.07);transition:box-shadow .18s ease,transform .18s ease;position:relative;overflow:hidden}
    .section-deployed .card{border-left:4px solid var(--teal)}
    .section-upcoming .card{border-left:4px solid var(--plum)}
    .card::after{content:'';position:absolute;top:0;right:0;width:80px;height:80px;background:radial-gradient(circle at top right,rgba(166,193,201,.12),transparent 70%);pointer-events:none}
    .card:hover{box-shadow:0 6px 20px rgba(32,72,85,.14);transform:translateY(-2px)}
    .card-top{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap}
    .badge{font-size:.63rem;font-weight:800;text-transform:uppercase;letter-spacing:.07em;padding:.22rem .6rem;border-radius:5px;color:white;flex-shrink:0}
    .badge-feature{background:var(--badge-feature)}.badge-bug{background:var(--badge-bug)}
    .badge-defect{background:var(--badge-defect)}.badge-story{background:var(--badge-story)}.badge-task{background:var(--badge-task)}
    .wi-id{font-size:.68rem;color:var(--muted);margin-left:auto;font-weight:500}
    .card-title{font-size:.93rem;font-weight:700;color:var(--text);line-height:1.4}
    .card-blurb{font-size:.86rem;color:#4a5c63;line-height:1.58}
    .card-footer{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:.4rem;margin-top:.15rem;padding-top:.65rem;border-top:1px solid var(--border)}
    .area-path{font-size:.7rem;color:var(--teal);background:rgba(32,72,85,.07);padding:.18rem .5rem;border-radius:4px;max-width:65%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:600}
    .date-chip{font-size:.7rem;color:var(--muted);font-weight:500;white-space:nowrap}
    .empty-state{background:var(--surface);border:2px dashed var(--border);border-radius:12px;padding:2.75rem;text-align:center;color:var(--muted)}
    .empty-state .empty-icon{font-size:2.5rem;margin-bottom:.75rem;display:block}
    .empty-state strong{display:block;font-size:1rem;color:var(--text);margin-bottom:.4rem;font-weight:700}
    .empty-state p{font-size:.875rem}
    @media(max-width:600px){header{padding:1.5rem}header h1{font-size:1.4rem}.cards{grid-template-columns:1fr}}
  </style>
</head>
<body>
<header>
  <div class="header-left">
    <div class="header-eyebrow">&#128203; MSI &middot; Team Data Troopers</div>
    <h1>&#10024; Data Services Release Notes</h1>
    <p class="subtitle">What we shipped &amp; what&apos;s coming next &#128640;</p>
  </div>
  <div class="header-meta">
    <div>&#128336; Last updated: <strong id="last-updated"></strong></div>
    <div>&#9200; Next refresh: <span id="countdown">calculating&hellip;</span></div>
  </div>
</header>
<main>
  <div class="refresh-bar">
    &#128260; This page auto-refreshes daily at 4:00 PM ET &mdash; data pulled fresh from Azure DevOps each weekday.
  </div>

  <section class="section-deployed">
    <div class="section-header">
      <span class="section-emoji">&#128674;</span>
      <h2>Deployed this week</h2>
      <span class="count">##DEPLOYED_COUNT## items</span>
    </div>
    ##DEPLOYED_SECTION##
  </section>

  <section class="section-upcoming">
    <div class="section-header">
      <span class="section-emoji">&#128302;</span>
      <h2>Coming in the next release</h2>
      <span class="count">##UPCOMING_COUNT## items</span>
    </div>
    ##UPCOMING_SECTION##
  </section>

</main>
<script>
  var now = new Date();
  document.getElementById('last-updated').textContent = now.toLocaleString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
    hour: 'numeric', minute: '2-digit', hour12: true
  });
  function getNext4pmEastern() {
    var nowUtc = Date.now();
    var jan = new Date(new Date().getFullYear(), 0, 1).getTimezoneOffset();
    var jul = new Date(new Date().getFullYear(), 6, 1).getTimezoneOffset();
    var isDST = new Date().getTimezoneOffset() < Math.max(jan, jul);
    var easternOffsetHours = isDST ? -4 : -5;
    var easternNow = new Date(nowUtc + easternOffsetHours * 3600 * 1000);
    var next4pm = new Date(easternNow);
    next4pm.setUTCHours(16, 0, 0, 0);
    if (next4pm <= easternNow) next4pm.setUTCDate(next4pm.getUTCDate() + 1);
    return next4pm.getTime() - easternOffsetHours * 3600 * 1000;
  }
  var countdownEl = document.getElementById('countdown');
  var fireAt = getNext4pmEastern();
  function updateCountdown() {
    var msLeft = fireAt - Date.now();
    if (msLeft <= 0) { location.reload(); return; }
    var h = Math.floor(msLeft / 3600000);
    var m = Math.floor((msLeft % 3600000) / 60000);
    var s = Math.floor((msLeft % 60000) / 1000);
    countdownEl.textContent = '4:00 PM ET (in ' + h + 'h ' + m + 'm ' + s + 's)';
  }
  updateCountdown();
  setInterval(updateCountdown, 1000);
</script>
</body>
</html>
'@

# ── MAIN ──────────────────────────────────────────────────────────────────────
Write-Host "=== Starting release notes refresh ==="

$deployedIds = @(Invoke-Wiql $DEPLOYED_WIQL)
$upcomingIds = @(Invoke-SavedQuery $NEXT_RELEASE_QID)
Write-Host "Deployed IDs: $($deployedIds.Count)  |  Upcoming IDs: $($upcomingIds.Count)"

$deployedItems = @(if ($deployedIds.Count -gt 0) { Get-WorkItemsBatch $deployedIds } else { @() })
$upcomingItems = @(if ($upcomingIds.Count  -gt 0) { Get-WorkItemsBatch $upcomingIds } else { @() })

$deployedIdSet = @{}; $deployedIds | ForEach-Object { $deployedIdSet[$_] = $true }
$upcomingItems = @($upcomingItems | Where-Object { -not $deployedIdSet.ContainsKey($_.fields.'System.Id') })

if ($deployedItems.Count -eq 0) {
    $deployedSection = '<div class="empty-state"><span class="empty-icon">&#128564;</span><strong>Nothing deployed yet this week</strong><p>Check back after the next release push &mdash; shipped items will appear here!</p></div>'
} else {
    $cards = ($deployedItems | ForEach-Object { Build-Card $_ '&#128640;' }) -join ''
    $deployedSection = "<div class=""cards"">$cards</div>"
}

if ($upcomingItems.Count -eq 0) {
    $upcomingSection = '<div class="empty-state"><span class="empty-icon">&#128336;</span><strong>No items queued for next release</strong><p>Nothing is currently flagged for the next release.</p></div>'
} else {
    $cards = ($upcomingItems | ForEach-Object { Build-Card $_ '&#9989;' }) -join ''
    $upcomingSection = "<div class=""cards"">$cards</div>"
}

$html = $HTML_TEMPLATE `
    -replace '##GENERATED_DATE##', (Get-Date -Format 'yyyy-MM-dd HH:mm') `
    -replace '##DEPLOYED_COUNT##', $deployedItems.Count `
    -replace '##DEPLOYED_SECTION##', $deployedSection `
    -replace '##UPCOMING_COUNT##', $upcomingItems.Count `
    -replace '##UPCOMING_SECTION##', $upcomingSection

[System.IO.File]::WriteAllText($OUT_PATH, $html, [System.Text.Encoding]::UTF8)
Write-Host "HTML written to $OUT_PATH ($([math]::Round($html.Length/1024,1)) KB)"
Write-Host "=== Done. Deployed: $($deployedItems.Count), Upcoming: $($upcomingItems.Count) ==="
