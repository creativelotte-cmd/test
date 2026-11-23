# Scheduled job: realtime chart -> Naver daily search -> (sample fallback) -> page dataset,
# then the weekly history (Hanteo weekly chart + Naver weekly search) for the analysis tool.
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'collect-chart.ps1') -NoBuild
& (Join-Path $PSScriptRoot 'collect-naver.ps1')
# sample rows only while no real search data exists
& (Join-Path $PSScriptRoot 'sample-trends.ps1')
& (Join-Path $PSScriptRoot 'build-data.ps1')

# Weekly history: failures here must never break the page update above
foreach ($s in 'collect-weekly.ps1', 'collect-naver-weekly.ps1', 'build-weekly.ps1') {
    try { & (Join-Path $PSScriptRoot $s) } catch { Write-Log "ERROR $s : $($_.Exception.Message)" }
}
