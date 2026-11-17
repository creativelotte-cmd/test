# Hourly job: music chart -> Google Trends (after approval) -> sample fallback -> rebuild dataset
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'collect-chart.ps1') -NoBuild
& (Join-Path $PSScriptRoot 'collect-google.ps1')
# TEMPORARY until Google approval; skips itself once real google_trends rows exist
& (Join-Path $PSScriptRoot 'sample-trends.ps1')
& (Join-Path $PSScriptRoot 'build-data.ps1')
