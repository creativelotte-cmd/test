# Builds data/weekly.json: 52-week history for the commercial-value analysis
# (weekly chart ranks + weekly Naver search interest per artist). Kept separate from
# eumwon-daily.json so the main page stays light. GitHub Pages serves it at ../data/weekly.json.
. (Join-Path $PSScriptRoot 'common.ps1')

$weekly = @(Read-CsvSafe (Join-Path $DataDir 'chart_weekly.csv'))
$search = @(Read-CsvSafe (Join-Path $DataDir 'search_weekly.csv'))
if (-not $weekly.Count) { Write-Log 'SKIP build weekly: no weekly chart data'; return }

$weeks = @($weekly | Sort-Object week_start | Select-Object week, week_start, week_end -Unique | ForEach-Object {
    [ordered]@{ week = $_.week; week_start = $_.week_start; week_end = $_.week_end } })
$weeks = @($weeks | Sort-Object { $_.week_start } | Group-Object { $_.week } | ForEach-Object { $_.Group[0] })

$dataset = [ordered]@{
    meta = [ordered]@{
        name = 'Jesictify weekly history'
        generated_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        chart_source = 'Hanteo Chart weekly digital chart (top 20), rank only (no score on weekly pages)'
        search_source = 'Naver DataLab search trend (NAVER API HUB), timeUnit=week, 52 weeks'
        search_note = 'interest = Naver relative search volume per week; anchor keyword (config/naver.json) weekly average over the window = 100; week_start = Naver period start'
        week_count = $weeks.Count
        artist_count = @($weekly | Select-Object -ExpandProperty artist -Unique).Count
    }
    weeks = $weeks
    chart_weekly = @($weekly | ForEach-Object { [ordered]@{
        week = $_.week; rank = [int]$_.rank; title = $_.title; artist = $_.artist; rank_move = $_.rank_move; album_id = $_.album_id } })
    search_weekly = @($search | ForEach-Object { [ordered]@{
        week_start = $_.week_start; artist = $_.artist; keyword = $_.keyword; interest = [double]$_.interest } })
}
Write-Utf8File (Join-Path $DataDir 'weekly.json') ($dataset | ConvertTo-Json -Depth 5 -Compress)
Write-Log "OK built weekly.json: $($weeks.Count) weeks, $($dataset.chart_weekly.Count) chart rows, $($dataset.search_weekly.Count) search rows"
