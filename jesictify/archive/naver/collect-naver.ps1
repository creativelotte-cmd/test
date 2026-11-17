# Collects Naver DataLab search trends (daily, last N days) for every artist and song
# in the latest Hanteo chart snapshot, and stores them in data/search_trends.csv.
#
# Scaling: Naver rescales each request to 0-100 and allows max 5 keyword groups per request.
# Every request therefore carries the same anchor keyword + 4 targets, and each value is
# converted to: interest = ratio / mean(anchor ratio in the same request) * 100
# => "anchor keyword's average daily search over the window = 100", comparable across requests.
param([switch]$Force)

. (Join-Path $PSScriptRoot 'common.ps1')

$ConfigPath = Join-Path $Root 'config\naver.json'
if (-not (Test-Path $ConfigPath)) { Write-Log 'SKIP naver: config\naver.json not found'; return }
$cfg = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
# Keys: config\naver.json, or user environment variables NAVER_CLIENT_ID / NAVER_CLIENT_SECRET
# (env vars avoid files entirely, e.g. on PCs where DRM encrypts files saved by editors)
if (-not $cfg.client_id)     { $cfg.client_id     = [Environment]::GetEnvironmentVariable('NAVER_CLIENT_ID', 'User') }
if (-not $cfg.client_secret) { $cfg.client_secret = [Environment]::GetEnvironmentVariable('NAVER_CLIENT_SECRET', 'User') }
if (-not $cfg.client_id -or -not $cfg.client_secret) { Write-Log 'SKIP naver: no keys (config\naver.json empty and NAVER_CLIENT_ID / NAVER_CLIENT_SECRET not set)'; return }
$Days   = if ($cfg.days) { [int]$cfg.days } else { 30 }
$Anchor = [string]$cfg.anchor_keyword
if (-not $Anchor) { Write-Log 'ERROR naver: anchor_keyword empty in config\naver.json'; exit 1 }

function Clean([string]$s) {
    # drop "(...)" / "[...]" parts and odd whitespace: "Popcorn" stays, "doh(D.O.)" -> "doh"
    $t = [regex]::Replace($s, '\s*[\(\[][^\)\]]*[\)\]]', '')
    $t = [regex]::Replace($t, '\s+', ' ').Trim()
    if ($t) { return $t } else { return $s.Trim() }
}

# --- targets from the latest chart snapshot ---
$chart = @(Read-CsvSafe $ChartCsv)
if (-not $chart.Count) { Write-Log 'SKIP naver: no chart data yet'; return }
$latestTime = ($chart | Sort-Object chart_time -Descending | Select-Object -First 1).chart_time
$latest = @($chart | Where-Object { $_.chart_time -eq $latestTime })
$artistKw = @{}; foreach ($a in @(Read-CsvSafe $ArtistsCsv)) { $artistKw[$a.artist] = $a.search_keyword }

$targets = @()
$seen = @{}
foreach ($e in $latest) {
    if (-not $seen.ContainsKey("A|$($e.artist)")) {
        $seen["A|$($e.artist)"] = $true
        $kw = if ($artistKw[$e.artist]) { Clean $artistKw[$e.artist] } else { Clean $e.artist }
        $targets += [pscustomobject]@{ target_type = 'artist'; artist = $e.artist; title = ''; keywords = @($kw) }
    }
    if (-not $seen.ContainsKey("S|$($e.artist)|$($e.title)")) {
        $seen["S|$($e.artist)|$($e.title)"] = $true
        $ca = Clean $(if ($artistKw[$e.artist]) { $artistKw[$e.artist] } else { $e.artist })
        $ct = Clean $e.title
        # song = "artist title" + "title artist" (title alone is too ambiguous: With, BAD, NEON ...)
        $targets += [pscustomobject]@{ target_type = 'song'; artist = $e.artist; title = $e.title; keywords = @("$ca $ct", "$ct $ca") }
    }
}

# --- skip if today's data for these exact targets is already stored ---
$existing = @(Read-CsvSafe $TrendsCsv)
$today = (Get-Date).ToString('yyyy-MM-dd')
if (-not $Force) {
    $have = @{}
    foreach ($r in $existing) { if ($r.source -eq 'naver_datalab' -and $r.fetched_at -like "$today*") { $have["$($r.target_type)|$($r.artist)|$($r.title)"] = $true } }
    $missing = @($targets | Where-Object { -not $have.ContainsKey("$($_.target_type)|$($_.artist)|$($_.title)") })
    if (-not $missing.Count) { Write-Log 'SKIP naver: all current targets already fetched today'; return }
}

# --- query Naver DataLab ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$endDate   = (Get-Date).Date.AddDays(-1)          # yesterday = last complete day
$startDate = $endDate.AddDays(-($Days - 1))
# api_mode "hub" (default): NAVER API HUB keys from the Naver Cloud console (required for keys issued after 2026-07-31)
# api_mode "developers": legacy developers.naver.com keys
if ($cfg.api_mode -eq 'developers') {
    $ApiUrl  = 'https://openapi.naver.com/v1/datalab/search'
    $headers = @{ 'X-Naver-Client-Id' = $cfg.client_id; 'X-Naver-Client-Secret' = $cfg.client_secret }
} else {
    $ApiUrl  = 'https://naverapihub.apigw.ntruss.com/search-trend/v1/search'
    $headers = @{ 'X-NCP-APIGW-API-KEY-ID' = $cfg.client_id; 'X-NCP-APIGW-API-KEY' = $cfg.client_secret }
}
$fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$newRows = @()
$calls = 0

for ($i = 0; $i -lt $targets.Count; $i += 4) {
    $batch = @($targets[$i..([Math]::Min($i + 3, $targets.Count - 1))])
    $groups = @(@{ groupName = 'anchor'; keywords = @($Anchor) })
    for ($k = 0; $k -lt $batch.Count; $k++) { $groups += @{ groupName = "t$k"; keywords = @($batch[$k].keywords) } }
    $body = @{
        startDate = $startDate.ToString('yyyy-MM-dd'); endDate = $endDate.ToString('yyyy-MM-dd')
        timeUnit = 'date'; keywordGroups = $groups
    } | ConvertTo-Json -Depth 5 -Compress

    try {
        $resp = Invoke-WebRequest -Uri $ApiUrl -Method Post -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
        $calls++
        $bytes = New-Object byte[] $resp.RawContentStream.Length
        $resp.RawContentStream.Position = 0
        [void]$resp.RawContentStream.Read($bytes, 0, $bytes.Length)
        $result = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg += ' ' + $_.ErrorDetails.Message }
        Write-Log "ERROR naver request failed: $msg"
        exit 1
    }

    $series = @{}
    foreach ($g in $result.results) {
        $m = @{}; foreach ($p in $g.data) { $m[$p.period] = [double]$p.ratio }
        $series[$g.title] = $m
    }
    $dates = @(); for ($d = $startDate; $d -le $endDate; $d = $d.AddDays(1)) { $dates += $d.ToString('yyyy-MM-dd') }
    $anchorVals = @($dates | ForEach-Object { if ($series['anchor'].ContainsKey($_)) { $series['anchor'][$_] } else { 0 } })
    $anchorMean = ($anchorVals | Measure-Object -Average).Average
    if (-not $anchorMean) { Write-Log "ERROR naver: anchor keyword returned no data"; exit 1 }

    for ($k = 0; $k -lt $batch.Count; $k++) {
        $t = $batch[$k]; $s = $series["t$k"]
        foreach ($dt in $dates) {
            $ratio = if ($s -and $s.ContainsKey($dt)) { $s[$dt] } else { 0 }
            $newRows += [pscustomobject]@{
                date = $dt; target_type = $t.target_type; artist = $t.artist; title = $t.title
                keyword = ($t.keywords -join ' | '); geo = 'KR'
                interest = [Math]::Round($ratio / $anchorMean * 100, 2)
                source = 'naver_datalab'; fetched_at = $fetchedAt
            }
        }
    }
    Start-Sleep -Milliseconds 300
}

# Replace stored naver rows for the refreshed targets; drop old SAMPLE rows entirely
$refreshed = @{}; foreach ($t in $targets) { $refreshed["$($t.target_type)|$($t.artist)|$($t.title)"] = $true }
$keep = @($existing | Where-Object {
    $_.source -ne 'sample' -and -not ($_.source -eq 'naver_datalab' -and $refreshed.ContainsKey("$($_.target_type)|$($_.artist)|$($_.title)"))
} | ForEach-Object {
    [pscustomobject]@{ date = $_.date; target_type = $_.target_type; artist = $_.artist; title = $_.title; keyword = $_.keyword
        geo = $_.geo; interest = $_.interest; source = $_.source; fetched_at = $_.fetched_at }
})
Write-CsvUtf8 (@($keep) + $newRows) $TrendsCsv
Write-Log "OK naver: $($targets.Count) targets ($calls requests), $($newRows.Count) rows, anchor='$Anchor' window $($startDate.ToString('yyyy-MM-dd'))..$($endDate.ToString('yyyy-MM-dd'))"
