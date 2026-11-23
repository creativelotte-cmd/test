# Commercial-value analysis engine (Step 3/4). Reads chart_weekly.csv + search_weekly.csv and writes
# data/analysis.json: per-artist score (0-100), grade, status tags, 5 metrics, and score history.
# Definitions: docs/commercial-score.md  (weights: power 30 / momentum 20 / longevity 20 / search 20 / breadth 10)
param([int]$HistoryWeeks = 12)

. (Join-Path $PSScriptRoot 'common.ps1')

$W = [ordered]@{ power = 0.30; momentum = 0.20; longevity = 0.20; search = 0.20; breadth = 0.10 }

$chart  = @(Read-CsvSafe (Join-Path $DataDir 'chart_weekly.csv'))
$search = @(Read-CsvSafe (Join-Path $DataDir 'search_weekly.csv'))
if (-not $chart.Count) { Write-Log 'SKIP analyze: no weekly chart data'; return }

function Clamp([double]$x, [double]$lo, [double]$hi) { [Math]::Max($lo, [Math]::Min($hi, $x)) }
function Avg($vals) { $v = @($vals); if ($v.Count) { ($v | Measure-Object -Average).Average } else { $null } }

# --- index weeks ---
$weeks = @($chart | Select-Object week, week_start, week_end -Unique | Sort-Object week_start |
    Group-Object week | ForEach-Object { $_.Group[0] } | Sort-Object week_start)
$wi = @{}; for ($i = 0; $i -lt $weeks.Count; $i++) { $wi[$weeks[$i].week] = $i }
$N = $weeks.Count
$artists = @($chart | Select-Object -ExpandProperty artist -Unique | Sort-Object)

# points[a][i] = sum(21 - rank); nsongs[a][i]; song history for re-entry detection
$points = @{}; $nsongs = @{}; $songWeeks = @{}
foreach ($a in $artists) { $points[$a] = New-Object double[] $N; $nsongs[$a] = New-Object int[] $N }
foreach ($r in $chart) {
    $i = $wi[$r.week]; $a = $r.artist; $rk = [int]$r.rank
    $points[$a][$i] += (21 - $rk); $nsongs[$a][$i]++
    $key = "$a|$($r.title)"
    if (-not $songWeeks.ContainsKey($key)) { $songWeeks[$key] = @{} }
    $songWeeks[$key][$i] = $rk
}

# search[a][i] by week_start
$sIdx = @{}; for ($i = 0; $i -lt $N; $i++) { $sIdx[$weeks[$i].week_start] = $i }
$sv = @{}
foreach ($a in $artists) { $sv[$a] = New-Object 'double[]' $N; for ($i = 0; $i -lt $N; $i++) { $sv[$a][$i] = -1 } }
foreach ($r in $search) { if ($sv.ContainsKey($r.artist) -and $sIdx.ContainsKey($r.week_start)) { $sv[$r.artist][$sIdx[$r.week_start]] = [double]$r.interest } }
function SVals($a, $from, $to) { @(for ($j = [Math]::Max(0, $from); $j -le $to; $j++) { if ($sv[$a][$j] -ge 0) { $sv[$a][$j] } }) }

function Score-Week([int]$i) {
    $univ = @($artists | Where-Object { $a = $_; @(0..$i | Where-Object { $points[$a][$_] -gt 0 }).Count -gt 0 })
    $maxp = ($univ | ForEach-Object { $points[$_][$i] } | Measure-Object -Maximum).Maximum
    if (-not $maxp) { $maxp = 1 }
    # search level percentile across the universe
    $lvl = @{}; foreach ($a in $univ) { $x = Avg (SVals $a ($i - 3) $i); $lvl[$a] = $(if ($null -eq $x) { 0 } else { $x }) }
    $sorted = @($univ | Sort-Object { $lvl[$_] })
    $pct = @{}; for ($k = 0; $k -lt $sorted.Count; $k++) { $pct[$sorted[$k]] = $(if ($sorted.Count -gt 1) { 100.0 * $k / ($sorted.Count - 1) } else { 100 }) }

    $out = @{}
    foreach ($a in $univ) {
        $p = $points[$a][$i]
        $prev = @(for ($j = [Math]::Max(0, $i - 4); $j -lt $i; $j++) { $points[$a][$j] })
        $prevAvg = if ($prev.Count) { Avg $prev } else { 0 }
        $mom = $p - $prevAvg
        $win = [Math]::Min(52, $i + 1)
        $inWeeks = @(for ($j = $i - $win + 1; $j -le $i; $j++) { if ($points[$a][$j] -gt 0) { 1 } }).Count
        $streak = 0; for ($j = $i; $j -ge 0 -and $points[$a][$j] -gt 0; $j--) { $streak++ }
        $sNow = $sv[$a][$i]
        $sPrev = Avg (SVals $a ($i - 4) ($i - 1))
        $chg = if ($sNow -ge 0 -and $sPrev) { ($sNow - $sPrev) / $sPrev } else { 0 }
        $ns = $nsongs[$a][$i]

        # square root softens the leader's dominance (one #1 song should not flatten everyone else)
        $s1 = 100.0 * [Math]::Sqrt($p / $maxp)
        $s2 = 50 + 50 * (Clamp ($mom / 20) -1 1)
        $s3 = 70.0 * $inWeeks / $win + 30.0 * [Math]::Min($streak, 12) / 12
        $s4 = 0.7 * $pct[$a] + 0.3 * (50 + 50 * (Clamp $chg -1 1))
        $s5 = switch ($ns) { 0 { 0 } 1 { 40 } 2 { 70 } default { 100 } }
        $total = $W.power * $s1 + $W.momentum * $s2 + $W.longevity * $s3 + $W.search * $s4 + $W.breadth * $s5
        $out[$a] = [ordered]@{
            score = [Math]::Round($total, 1)
            metrics = [ordered]@{ power = [Math]::Round($s1, 1); momentum = [Math]::Round($s2, 1); longevity = [Math]::Round($s3, 1); search = [Math]::Round($s4, 1); breadth = $s5 }
            raw = [ordered]@{ chart_points = $p; points_prev4_avg = [Math]::Round($prevAvg, 1); weeks_in_chart = $inWeeks; window_weeks = $win
                streak = $streak; songs_in_chart = $ns; search_week = $(if ($sNow -ge 0) { $sNow } else { $null })
                search_level_4w = [Math]::Round($lvl[$a], 1); search_change = [Math]::Round($chg, 3) }
        }
    }
    return $out
}

function Grade([double]$s) { if ($s -ge 80) { 'S' } elseif ($s -ge 65) { 'A' } elseif ($s -ge 50) { 'B' } else { 'C' } }

# --- score the latest weeks ---
$last = $N - 1
$first = [Math]::Max(0, $N - $HistoryWeeks)
$byWeek = @{}; for ($i = $first; $i -le $last; $i++) { $byWeek[$i] = Score-Week $i }
$cur = $byWeek[$last]; $prevW = if ($last -gt $first) { $byWeek[$last - 1] } else { @{} }

$rows = @()
foreach ($a in $cur.Keys) {
    $m = $cur[$a]; $raw = $m.raw
    $inNow = $raw.chart_points -gt 0
    $wasPrev = $last -gt 0 -and $points[$a][$last - 1] -gt 0
    $firstIdx = (@(0..$last | Where-Object { $points[$a][$_] -gt 0 }) | Select-Object -First 1)

    # re-entry: an older song (first charted >= 12 weeks ago) at its best rank ever this week
    $reentry = $false; $songs = @()
    foreach ($key in $songWeeks.Keys) {
        if (-not $key.StartsWith("$a|")) { continue }
        $h = $songWeeks[$key]
        if (-not $h.ContainsKey($last)) { continue }
        $fi = ($h.Keys | Measure-Object -Minimum).Minimum
        $before = @($h.Keys | Where-Object { $_ -lt $last } | ForEach-Object { $h[$_] })
        if ($fi -le $last - 12 -and $before.Count -and $h[$last] -lt ($before | Measure-Object -Minimum).Minimum) { $reentry = $true }
        $songs += [ordered]@{ title = $key.Substring($a.Length + 1); rank = $h[$last]; weeks_on_chart = $h.Count; first_week = $weeks[$fi].week }
    }
    $tags = @()
    if ($inNow -and $firstIdx -ge $last - 1 -and $last -ge 8) { $tags += 'new' }
    if ($reentry) { $tags += 'reentry' }
    $momRaw = $raw.chart_points - $raw.points_prev4_avg
    if ($inNow -and ($momRaw -ge 5 -or ($raw.search_change -ge 0.3 -and $momRaw -ge 0))) { $tags += 'rising' }
    if (($inNow -and $momRaw -le -5) -or ($wasPrev -and -not $inNow)) { $tags += 'falling' }
    if (-not $inNow -and -not $wasPrev) { $tags += 'out' }
    if (-not $tags.Count) { $tags += 'steady' }

    $hist = @(for ($i = $first; $i -le $last; $i++) { if ($byWeek[$i].ContainsKey($a)) { [ordered]@{ week = $weeks[$i].week; score = $byWeek[$i][$a].score } } })
    $rows += [pscustomobject]([ordered]@{
        artist = $a; score = $m.score; grade = Grade $m.score
        prev_score = $(if ($prevW.ContainsKey($a)) { $prevW[$a].score } else { $null })
        tags = $tags; metrics = $m.metrics; raw = $raw
        songs = @($songs | Sort-Object { $_.rank }); history = $hist
    })
}
$rows = @($rows | Sort-Object score -Descending)
for ($k = 0; $k -lt $rows.Count; $k++) { $rows[$k] | Add-Member -NotePropertyName rank -NotePropertyValue ($k + 1) }

$dataset = [ordered]@{
    meta = [ordered]@{
        name = 'Jesictify commercial-value analysis'
        generated_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        week = $weeks[$last].week; week_start = $weeks[$last].week_start; week_end = $weeks[$last].week_end
        weights = $W
        grades = 'S >= 80, A >= 65, B >= 50, C < 50'
        tags = 'new, reentry, rising, falling, steady, out'
        definitions = 'docs/commercial-score.md'
        artist_count = $rows.Count
    }
    artists = $rows
}
Write-Utf8File (Join-Path $DataDir 'analysis.json') ($dataset | ConvertTo-Json -Depth 6 -Compress)
Write-Log "OK analysis: week $($weeks[$last].week), $($rows.Count) artists, top=$($rows[0].artist) $($rows[0].score)"
