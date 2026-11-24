# Collects the Hanteo realtime digital chart (top 20) and appends it to data/chart_snapshots.csv.
# Only the public HTML page is read; /api/ is disallowed by hanteochart.com robots.txt.
param([switch]$NoBuild)

. (Join-Path $PSScriptRoot 'common.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Url = 'https://www.hanteochart.com/ko/charts/digital/real'

try {
    # cache-buster + no-cache headers: GitHub's runners were served copies of the page that were hours/days old
    $resp = Invoke-WebRequest -Uri ($Url + '?_=' + [DateTime]::UtcNow.Ticks) -UseBasicParsing -TimeoutSec 30 `
        -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) EumwonDaily/1.0' `
        -Headers @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }
    $bytes = New-Object byte[] $resp.RawContentStream.Length
    $resp.RawContentStream.Position = 0
    [void]$resp.RawContentStream.Read($bytes, 0, $bytes.Length)
    $html = [System.Text.Encoding]::UTF8.GetString($bytes)
} catch {
    Write-Log "ERROR fetch failed: $($_.Exception.Message)"
    exit 1
}

function Decode([string]$s) { ([System.Net.WebUtility]::HtmlDecode($s)).Trim() }

# Aggregation time, e.g. "2026.11.17 11:55" (KST)
$tm = [regex]::Match($html, 'chart-resultDatetime">[^<]*?(\d{4})\.(\d{2})\.(\d{2}) (\d{2}):(\d{2})')
if (-not $tm.Success) { Write-Log 'ERROR aggregation time not found (page layout changed?)'; exit 1 }
$chartTime = '{0}-{1}-{2}T{3}:{4}:00+09:00' -f $tm.Groups[1].Value, $tm.Groups[2].Value, $tm.Groups[3].Value, $tm.Groups[4].Value, $tm.Groups[5].Value
$collectedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
# A realtime chart older than 3 hours is a stale cached page, not the current chart: don't store it
$ageH = ((Get-Date) - [datetime]::ParseExact($chartTime.Substring(0, 16), 'yyyy-MM-ddTHH:mm', $null)).TotalHours
if ($ageH -gt 3) {
    Write-Log ("WARN stale realtime page: chart time {0} is {1:N0}h old, not stored" -f $chartTime, $ageH)
    if (-not $NoBuild) { & (Join-Path $PSScriptRoot 'build-data.ps1') }
    return
}

$segments = [regex]::Split($html, 'class="chart-item rank-data') | Select-Object -Skip 1
$entries = @()
foreach ($seg in $segments) {
    $rank   = [regex]::Match($seg, 'rank-container"><div class="top">\s*(\d+)\s*</div>')
    $bottom = [regex]::Match($seg, 'rank-container">.*?<div class="bottom">(.*?)</div>')
    $title  = [regex]::Match($seg, 'row-container"><div class="top" title="([^"]*)"')
    $artist = [regex]::Match($seg, '<pre class="left" title="([^"]*)"')
    $score  = [regex]::Match($seg, 'stat-container"><div class="left">\s*([\d,\.]+)\s*</div>')
    $album  = [regex]::Match($seg, '/album/(\d+)_')
    if (-not ($rank.Success -and $title.Success -and $artist.Success -and $score.Success)) { continue }

    # Rank movement: icon name (zero/up/down/new...) plus any visible number
    $moveIcon = ''; $moveText = ''
    if ($bottom.Success) {
        $ic = [regex]::Match($bottom.Groups[1].Value, 'chart_rank_([a-z_]+)\.png')
        if ($ic.Success) { $moveIcon = $ic.Groups[1].Value }
        $moveText = (Decode ([regex]::Replace($bottom.Groups[1].Value, '<[^>]+>', '')))
    }

    $entries += [pscustomobject]@{
        chart_time   = $chartTime
        collected_at = $collectedAt
        rank         = [int]$rank.Groups[1].Value
        title        = Decode $title.Groups[1].Value
        artist       = Decode $artist.Groups[1].Value
        score        = [double]($score.Groups[1].Value -replace ',', '')
        rank_move    = $moveIcon
        rank_move_n  = $moveText
        album_id     = $(if ($album.Success) { $album.Groups[1].Value } else { '' })
        source       = 'hanteo_digital_realtime'
    }
    if ($entries.Count -ge 20) { break }
}

if ($entries.Count -eq 0) { Write-Log 'ERROR no chart rows parsed (page layout changed?)'; exit 1 }

$existing = Read-CsvSafe $ChartCsv
if ($existing | Where-Object { $_.chart_time -eq $chartTime } | Select-Object -First 1) {
    Write-Log "SKIP snapshot $chartTime already stored"
} else {
    Write-CsvUtf8 (@($existing) + $entries) $ChartCsv
    Write-Log "OK stored $($entries.Count) rows for $chartTime"
}

# Register newly seen artists for search-volume tracking (search_keyword is editable by hand)
$artists = @(Read-CsvSafe $ArtistsCsv)
$known = @{}; foreach ($a in $artists) { $known[$a.artist] = $true }
$added = 0
foreach ($e in $entries) {
    if (-not $known.ContainsKey($e.artist)) {
        $artists += [pscustomobject]@{ artist = $e.artist; search_keyword = $e.artist; first_seen = $chartTime.Substring(0, 10); active = 'Y' }
        $known[$e.artist] = $true; $added++
    }
}
if ($added -gt 0 -or -not (Test-Path $ArtistsCsv)) {
    Write-CsvUtf8 $artists $ArtistsCsv
    Write-Log "OK registered $added new artist(s)"
}

if (-not $NoBuild) { & (Join-Path $PSScriptRoot 'build-data.ps1') }
