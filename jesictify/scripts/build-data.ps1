# Combines the CSV stores into one dataset:
#   data/eumwon-daily.json  -> for Claude / analysis tools
#   web/data.js             -> for the web page (works when index.html is opened directly)
param([int]$HistoryDays = 7)

. (Join-Path $PSScriptRoot 'common.ps1')

$chart   = Read-CsvSafe $ChartCsv
$artists = Read-CsvSafe $ArtistsCsv
$trends  = Read-CsvSafe $TrendsCsv

function ToChartRow($r) {
    [ordered]@{
        chart_time = $r.chart_time; rank = [int]$r.rank; title = $r.title; artist = $r.artist
        score = [double]$r.score; rank_move = $r.rank_move; rank_move_n = $r.rank_move_n; album_id = $r.album_id
    }
}

$latestTime = ($chart | Sort-Object chart_time -Descending | Select-Object -First 1).chart_time
$latest = @($chart | Where-Object { $_.chart_time -eq $latestTime } | Sort-Object { [int]$_.rank } | ForEach-Object { ToChartRow $_ })

$cutoff = (Get-Date).AddDays(-$HistoryDays).ToString('yyyy-MM-ddTHH:mm')
$history = @($chart | Where-Object { $_.chart_time -ge $cutoff } | Sort-Object chart_time, { [int]$_.rank } | ForEach-Object { ToChartRow $_ })

$trendRows = @($trends | Sort-Object target_type, artist, title, date | ForEach-Object {
    [ordered]@{
        date = $_.date; target_type = $(if ($_.target_type) { $_.target_type } else { 'artist' })
        artist = $_.artist; title = $_.title; keyword = $_.keyword; geo = $_.geo
        interest = [double]$_.interest; source = $_.source
    }
})

$trendSources = @($trends | Select-Object -ExpandProperty source -Unique)

$dataset = [ordered]@{
    meta = [ordered]@{
        name           = 'Eumwon Daily'
        generated_at   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        chart_source   = 'Hanteo Chart realtime digital chart (top 20) https://www.hanteochart.com/ko/charts/digital/real'
        chart_metric   = 'score = Hanteo digital index (eumwon jisu)'
        search_source  = 'Google Trends API (alpha), geo KR, daily, last 30 days (approval pending)'
        search_is_sample = ($trendSources -contains 'sample')
        search_has_data  = ($trendSources -contains 'google_trends')
        search_note    = 'interest = Google relative search interest (consistently scaled across requests), not absolute counts; latest date lags about 2 days; rows with source=sample are placeholder data'
        snapshot_count = @($chart | Select-Object -ExpandProperty chart_time -Unique).Count
    }
    latest_chart  = [ordered]@{ chart_time = $latestTime; entries = $latest }
    chart_history = $history
    artists       = @($artists)
    search_trends = $trendRows
}

$json = $dataset | ConvertTo-Json -Depth 6 -Compress
Write-Utf8File $JsonOut $json
Write-Utf8File $JsOut ("window.EUMWON_DATA = " + $json + ";`n")
Write-Log "OK built dataset: latest=$latestTime, history rows=$($history.Count), trend rows=$($trendRows.Count)"
