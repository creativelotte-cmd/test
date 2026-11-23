# Collects Hanteo WEEKLY digital charts (top 20) into data/chart_weekly.csv.
# First run backfills the last $Weeks ISO weeks; later runs only fetch weeks not stored yet.
# Weekly pages show rank / title / artist only (no score). Public HTML only (/api/ is robots-disallowed).
param([int]$Weeks = 52)

. (Join-Path $PSScriptRoot 'common.ps1')

$WeeklyCsv = Join-Path $DataDir 'chart_weekly.csv'

function Decode([string]$s) { ([System.Net.WebUtility]::HtmlDecode($s)).Trim() }
function IsoWeekId([datetime]$monday) {
    $thu = $monday.AddDays(3)
    '{0}-W{1:00}' -f $thu.Year, ([Math]::Floor(($thu.DayOfYear - 1) / 7) + 1)
}

$existing = @(Read-CsvSafe $WeeklyCsv)
$have = @{}; foreach ($r in $existing) { $have[$r.week] = $true }

$today = (Get-Date).Date
$thisMonday = $today.AddDays(-(([int]$today.DayOfWeek + 6) % 7))
$collectedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$newRows = @(); $fetched = 0; $notReady = 0

for ($i = $Weeks; $i -ge 1; $i--) {
    $mon = $thisMonday.AddDays(-7 * $i)
    $wid = IsoWeekId $mon
    if ($have.ContainsKey($wid)) { continue }
    try {
        $html = Get-HanteoHtml "https://www.hanteochart.com/ko/charts/digital/weekly/$wid"
    } catch {
        # 404 = the newest week is not published yet (normal for a few days after the week ends)
        if ($_.Exception.Message -match '404') { $notReady++ } else { Write-Log "ERROR weekly $wid fetch failed: $($_.Exception.Message)" }
        continue
    }
    $fetched++
    # The page must show exactly this week, otherwise it is not published yet (site falls back to the latest week)
    $want = $mon.ToString('yyyy.MM.dd')
    if ($html -notmatch [regex]::Escape($want) + '\s*~') { $notReady++; continue }

    $rows = @()
    foreach ($seg in ([regex]::Split($html, 'class="chart-item rank-data') | Select-Object -Skip 1)) {
        $rank   = [regex]::Match($seg, 'rank-container"><div class="top">\s*(\d+)\s*</div>')
        $title  = [regex]::Match($seg, 'row-container"><div class="top" title="([^"]*)"')
        $artist = [regex]::Match($seg, '<pre class="left" title="([^"]*)"')
        $ic     = [regex]::Match($seg, 'chart_rank_([a-z_]+)\.png')
        $album  = [regex]::Match($seg, '/album/(\d+)_')
        if (-not ($rank.Success -and $title.Success -and $artist.Success)) { continue }
        $rows += [pscustomobject]@{
            week = $wid; week_start = $mon.ToString('yyyy-MM-dd'); week_end = $mon.AddDays(6).ToString('yyyy-MM-dd')
            rank = [int]$rank.Groups[1].Value; title = Decode $title.Groups[1].Value; artist = Decode $artist.Groups[1].Value
            rank_move = $(if ($ic.Success) { $ic.Groups[1].Value } else { '' })
            album_id = $(if ($album.Success) { $album.Groups[1].Value } else { '' })
            source = 'hanteo_digital_weekly'; collected_at = $collectedAt
        }
        if ($rows.Count -ge 20) { break }
    }
    if ($rows.Count) { $newRows += $rows } else { Write-Log "ERROR weekly $wid no rows parsed (layout changed?)" }
    Start-Sleep -Milliseconds 800
}

if ($newRows.Count) {
    $all = @($existing) + $newRows | Sort-Object week_start, { [int]$_.rank }
    Write-CsvUtf8 $all $WeeklyCsv
    $wk = @($newRows | Select-Object -ExpandProperty week -Unique)
    Write-Log "OK weekly: stored $($wk.Count) week(s) $($wk[0])..$($wk[-1]) ($($newRows.Count) rows)"

    # register newly seen artists (same list the search collectors use)
    $artists = @(Read-CsvSafe $ArtistsCsv)
    $known = @{}; foreach ($a in $artists) { $known[$a.artist] = $true }
    $added = 0
    foreach ($e in $newRows) {
        if (-not $known.ContainsKey($e.artist)) {
            $artists += [pscustomobject]@{ artist = $e.artist; search_keyword = $e.artist; first_seen = $e.week_start; active = 'Y' }
            $known[$e.artist] = $true; $added++
        }
    }
    if ($added) { Write-CsvUtf8 $artists $ArtistsCsv; Write-Log "OK weekly: registered $added new artist(s)" }
} elseif ($notReady) {
    Write-Log "SKIP weekly: latest week not published yet"
} else {
    Write-Log "SKIP weekly: all $Weeks weeks already stored"
}
