# TEMPORARY: SAMPLE search-interest data for every artist and song in the latest chart,
# used only until Google Trends API (alpha) approval. Every row is marked source=sample.
# Mimics the Google API shape: daily values, geo KR, latest date = today - 2 (API lag).
# Skipped automatically once real google_trends rows exist.
param([int]$Days = 30)

. (Join-Path $PSScriptRoot 'common.ps1')

$existing = @(Read-CsvSafe $TrendsCsv)
if ($existing | Where-Object { $_.source -eq 'google_trends' } | Select-Object -First 1) {
    Write-Log 'SKIP sample trends: real Google data present'
    return
}
$targets = @(Get-SearchTargets)
if (-not $targets.Count) { Write-Log 'SKIP sample trends: no chart data yet'; return }

$end = (Get-Date).Date.AddDays(-2)
$fetchedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$rows = @()
foreach ($t in $targets) {
    $seed = 17
    foreach ($ch in ("$($t.target_type)|$($t.keyword)").ToCharArray()) { $seed = ($seed * 31 + [int]$ch) % 2147483647 }
    $rnd = New-Object System.Random($seed)
    $scale = if ($t.target_type -eq 'song') { 0.45 } else { 1.0 }   # songs searched less than artists
    $base  = (8 + $rnd.NextDouble() * 55) * $scale
    $trend = ($rnd.NextDouble() - 0.4) * 0.8 * $scale
    $spike = $rnd.Next(0, $Days)
    for ($i = $Days - 1; $i -ge 0; $i--) {
        $d = $end.AddDays(-$i)
        $k = $Days - 1 - $i
        $weekend = if ($d.DayOfWeek -in 'Saturday', 'Sunday') { 1.12 } else { 1.0 }
        $bump = 1 + 1.6 * [Math]::Exp(-[Math]::Pow(($k - $spike) / 1.8, 2))
        $v = ($base + $trend * $k) * $weekend * $bump * (0.9 + $rnd.NextDouble() * 0.2)
        $rows += [pscustomobject]@{
            date = $d.ToString('yyyy-MM-dd'); target_type = $t.target_type; artist = $t.artist; title = $t.title
            keyword = $t.keyword; geo = 'KR'; interest = [Math]::Round([Math]::Max(0.5, $v), 1)
            source = 'sample'; fetched_at = $fetchedAt
        }
    }
}
Write-CsvUtf8 $rows $TrendsCsv
Write-Log "OK wrote $($rows.Count) SAMPLE rows for $($targets.Count) targets (artists + songs)"
