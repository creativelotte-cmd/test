# YouTube view counts for every song in the latest chart snapshot (YouTube Data API v3).
#  1) Video matching (search.list = 100 quota units): only for songs not yet in data/youtube_videos.csv.
#     Query "artist title MV", region KR; prefers a result whose title contains the song title.
#     Wrong match? Edit video_id in youtube_videos.csv and set match=manual (never overwritten).
#  2) Stats (videos.list = 1 unit per 50 videos): every run -> data/youtube_stats.csv snapshot.
# Daily quota is 10,000 units: ~20 new songs/day (2,000) + 24 hourly stat calls (24) fits easily.
# Key: user environment variable YOUTUBE_API_KEY (set with scripts/set-youtube-key.ps1).
. (Join-Path $PSScriptRoot 'common.ps1')

$key = [Environment]::GetEnvironmentVariable('YOUTUBE_API_KEY', 'User')
if (-not $key) { $key = $env:YOUTUBE_API_KEY }
if (-not $key) { Write-Log 'SKIP youtube: YOUTUBE_API_KEY not set (run scripts\set-youtube-key.ps1)'; return }
$enc = { param($s) [Uri]::EscapeDataString($s) }

$songs = @(Get-SearchTargets | Where-Object { $_.target_type -eq 'song' })
if (-not $songs.Count) { Write-Log 'SKIP youtube: no chart data yet'; return }

# --- 1) match new songs to a video ---
$videos = @(Read-CsvSafe $YtVideosCsv)
$known = @{}; foreach ($v in $videos) { $known["$($v.artist)|$($v.title)"] = $true }
$matched = 0
foreach ($s in $songs) {
    if ($known.ContainsKey("$($s.artist)|$($s.title)")) { continue }
    $q = "$($s.keyword) MV"
    $url = 'https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&maxResults=5&regionCode=KR&relevanceLanguage=ko' +
           '&q=' + (& $enc $q) + '&key=' + $key
    try { $r = Get-JsonUtf8 $url } catch {
        $msg = $_.Exception.Message; if ($_.ErrorDetails) { $msg += ' ' + $_.ErrorDetails.Message }
        Write-Log "ERROR youtube search failed: $msg"; break
    }
    $items = @($r.items)
    if (-not $items.Count) { Write-Log "WARN youtube: no video for '$q'"; continue }
    $want = (Clean-Keyword $s.title).ToLower()
    $pick = $items | Where-Object { ([System.Net.WebUtility]::HtmlDecode($_.snippet.title)).ToLower().Contains($want) } | Select-Object -First 1
    $match = 'auto'
    if (-not $pick) { $pick = $items[0]; $match = 'auto_low' }   # title not found in result: check by hand
    $videos += [pscustomobject]@{
        artist = $s.artist; title = $s.title; video_id = $pick.id.videoId
        video_title = [System.Net.WebUtility]::HtmlDecode($pick.snippet.title)
        channel = [System.Net.WebUtility]::HtmlDecode($pick.snippet.channelTitle)
        published_at = $pick.snippet.publishedAt; match = $match; query = $q
        matched_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    }
    $known["$($s.artist)|$($s.title)"] = $true; $matched++
}
if ($matched) { Write-CsvUtf8 $videos $YtVideosCsv; Write-Log "OK youtube: matched $matched new song(s) to videos" }

# --- 2) view statistics for the current chart songs ---
$byKey = @{}; foreach ($v in $videos) { $byKey["$($v.artist)|$($v.title)"] = $v }
$current = @($songs | ForEach-Object { $byKey["$($_.artist)|$($_.title)"] } | Where-Object { $_ -and $_.video_id })
if (-not $current.Count) { Write-Log 'SKIP youtube stats: no matched videos'; return }

$collectedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
$rows = @()
for ($i = 0; $i -lt $current.Count; $i += 50) {
    $chunk = @($current[$i..([Math]::Min($i + 49, $current.Count - 1))])
    $ids = ($chunk | ForEach-Object { $_.video_id } | Select-Object -Unique) -join ','
    try { $r = Get-JsonUtf8 ("https://www.googleapis.com/youtube/v3/videos?part=statistics&id=$ids&key=$key") } catch {
        $msg = $_.Exception.Message; if ($_.ErrorDetails) { $msg += ' ' + $_.ErrorDetails.Message }
        Write-Log "ERROR youtube stats failed: $msg"; exit 1
    }
    $stats = @{}; foreach ($it in $r.items) { $stats[$it.id] = $it.statistics }
    foreach ($v in $chunk) {
        $st = $stats[$v.video_id]; if (-not $st) { continue }
        $rows += [pscustomobject]@{
            collected_at = $collectedAt; artist = $v.artist; title = $v.title; video_id = $v.video_id
            view_count = [int64]$st.viewCount
            like_count = $(if ($st.likeCount) { [int64]$st.likeCount } else { '' })
            comment_count = $(if ($st.commentCount) { [int64]$st.commentCount } else { '' })
        }
    }
}
$all = @(Read-CsvSafe $YtStatsCsv) + $rows
Write-CsvUtf8 $all $YtStatsCsv
Write-Log "OK youtube: stored view stats for $($rows.Count) video(s)"
