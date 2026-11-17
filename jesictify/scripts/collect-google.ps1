# Google Trends API (alpha) collector for every artist and song in the latest chart snapshot.
# STATUS: waiting for alpha approval. The API's auth method and request format are only given
# to approved testers, so the actual call is implemented after the approval email arrives.
#
# Target list and storage format are already fixed so the page and analysis need no change:
#   data/search_trends.csv: date, target_type(artist/song), artist, title, keyword, geo, interest, source=google_trends, fetched_at
#   artist keyword = artists.csv search_keyword; song keyword = "artist title"
. (Join-Path $PSScriptRoot 'common.ps1')

$cfgPath = Join-Path $Root 'config\google.json'
$cfg = if (Test-Path $cfgPath) { Get-Content -Raw -Encoding UTF8 $cfgPath | ConvertFrom-Json } else { $null }
if (-not $cfg -or -not $cfg.approved) {
    Write-Log 'SKIP google: Google Trends API approval pending (config\google.json approved=false)'
    return
}

# TODO after approval: build targets (see Get-SearchTargets), call the API per the approval email,
# write rows with source=google_trends, then remove sample rows.
Write-Log 'ERROR google: approved=true but the API call is not implemented yet'
exit 1
