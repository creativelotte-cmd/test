# Collects Naver DataLab WEEKLY search trends (last $Weeks weeks) for every artist that has
# appeared in the weekly chart or the realtime chart. Stored in data/search_weekly.csv.
# Refreshed once per ISO week (or when new artists appear). Same anchor scaling as collect-naver.ps1:
# interest = ratio / mean(anchor ratio in the same request) * 100  (anchor's weekly average = 100)
param([int]$Weeks = 52, [switch]$Force)

. (Join-Path $PSScriptRoot 'common.ps1')

$WeeklyCsv = Join-Path $DataDir 'chart_weekly.csv'
$SearchWeeklyCsv = Join-Path $DataDir 'search_weekly.csv'

$ConfigPath = Join-Path $Root 'config\naver.json'
if (-not (Test-Path $ConfigPath)) { Write-Log 'SKIP naver weekly: config\naver.json not found'; return }
$cfg = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
$cid = [Environment]::GetEnvironmentVariable('NAVER_CLIENT_ID', 'User');     if (-not $cid) { $cid = $env:NAVER_CLIENT_ID }
$csc = [Environment]::GetEnvironmentVariable('NAVER_CLIENT_SECRET', 'User'); if (-not $csc) { $csc = $env:NAVER_CLIENT_SECRET }
if (-not $cid -or -not $csc) { Write-Log 'SKIP naver weekly: no keys'; return }
$Anchor = [string]$cfg.anchor_keyword

# --- targets: every artist seen in weekly or realtime charts ---
$kwMap = @{}; foreach ($a in @(Read-CsvSafe $ArtistsCsv)) { $kwMap[$a.artist] = $a.search_keyword }
$names = @(@(Read-CsvSafe $WeeklyCsv) + @(Read-CsvSafe $ChartCsv) | Select-Object -ExpandProperty artist -Unique | Sort-Object)
if (-not $names.Count) { Write-Log 'SKIP naver weekly: no chart data'; return }

# --- refresh rule: once per ISO week, plus any artist not fetched yet ---
# Reference day = yesterday, so on a Monday the just-ended week (Sunday not fully aggregated yet) is not fetched
$today = (Get-Date).Date.AddDays(-1)
$thisMonday = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7))
$existing = @(Read-CsvSafe $SearchWeeklyCsv)
$fetchedThisWeek = @{}
foreach ($r in $existing) { if ([datetime]$r.fetched_at.Substring(0, 10) -ge $thisMonday) { $fetchedThisWeek[$r.artist] = $true } }
$targets = if ($Force) { $names } else { @($names | Where-Object { -not $fetchedThisWeek.ContainsKey($_) }) }
if (-not $targets.Count) { Write-Log 'SKIP naver weekly: all artists fetched this week'; return }

# window = last $Weeks complete weeks (Mon..Sun)
$endDate = $thisMonday.AddDays(-1)
$startDate = $thisMonday.AddDays(-7 * $Weeks)
$headers = @{ 'X-NCP-APIGW-API-KEY-ID' = $cid; 'X-NCP-APIGW-API-KEY' = $csc }
$fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$newRows = @(); $calls = 0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

for ($i = 0; $i -lt $targets.Count; $i += 4) {
    $batch = @($targets[$i..([Math]::Min($i + 3, $targets.Count - 1))])
    $groups = @(@{ groupName = 'anchor'; keywords = @($Anchor) })
    for ($k = 0; $k -lt $batch.Count; $k++) {
        $kw = Clean-Keyword $(if ($kwMap[$batch[$k]]) { $kwMap[$batch[$k]] } else { $batch[$k] })
        $groups += @{ groupName = "t$k"; keywords = @($kw) }
    }
    $body = @{ startDate = $startDate.ToString('yyyy-MM-dd'); endDate = $endDate.ToString('yyyy-MM-dd'); timeUnit = 'week'; keywordGroups = $groups } |
        ConvertTo-Json -Depth 5 -Compress
    try {
        $resp = Invoke-WebRequest -Uri 'https://naverapihub.apigw.ntruss.com/search-trend/v1/search' -Method Post -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -UseBasicParsing -TimeoutSec 30
        $calls++
        $result = [Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray()) | ConvertFrom-Json
    } catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg += ' ' + $_.ErrorDetails.Message }
        Write-Log "ERROR naver weekly request failed: $msg"
        break   # keep what was fetched so far
    }
    $series = @{}
    foreach ($g in $result.results) { $m = @{}; foreach ($p in $g.data) { $m[$p.period] = [double]$p.ratio }; $series[$g.title] = $m }
    $periods = @($series['anchor'].Keys | Sort-Object)
    $anchorMean = (@($series['anchor'].Values) | Measure-Object -Average).Average
    if (-not $anchorMean) { Write-Log 'ERROR naver weekly: anchor returned no data'; break }
    for ($k = 0; $k -lt $batch.Count; $k++) {
        $s = $series["t$k"]
        $kw = ($groups[$k + 1].keywords -join ' | ')
        foreach ($p in $periods) {
            $ratio = if ($s -and $s.ContainsKey($p)) { $s[$p] } else { 0 }
            $newRows += [pscustomobject]@{
                week_start = $p; artist = $batch[$k]; keyword = $kw
                interest = [Math]::Round($ratio / $anchorMean * 100, 2)
                source = 'naver_datalab_week'; fetched_at = $fetchedAt
            }
        }
    }
    Start-Sleep -Milliseconds 300
}

if (-not $newRows.Count) { return }
$done = @{}; foreach ($r in $newRows) { $done[$r.artist] = $true }
$keep = @($existing | Where-Object { -not $done.ContainsKey($_.artist) })
Write-CsvUtf8 (@($keep) + $newRows | Sort-Object artist, week_start) $SearchWeeklyCsv
Write-Log "OK naver weekly: $($done.Count) artists ($calls requests), $($newRows.Count) rows, window $($startDate.ToString('yyyy-MM-dd'))..$($endDate.ToString('yyyy-MM-dd'))"
