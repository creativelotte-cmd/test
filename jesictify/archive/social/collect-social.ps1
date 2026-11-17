# Collects the Hanteo weekly SOCIAL chart (artist top 20, "social index" from global SNS data)
# into data/social_weekly.csv. Public HTML pages only (/api/ is disallowed by robots.txt).
#   - current week: rank + social index score
#   - past weeks (-Backfill): Hanteo shows rank only for past weeks, so score stays empty
# One page request per run; a week already stored with a score is skipped.
param([switch]$Backfill)

. (Join-Path $PSScriptRoot 'common.ps1')
$Base = 'https://www.hanteochart.com/ko/charts/social/weekly'

function Parse-Social([string]$html, [string]$weekLabel) {
    $p = [regex]::Match($html, 'chart-resultDatetime">[^<]*?(\d{4})\.(\d{2})\.(\d{2})\s*~\s*(\d{4})\.(\d{2})\.(\d{2})')
    if (-not $p.Success) { return @() }
    $start = '{0}-{1}-{2}' -f $p.Groups[1].Value, $p.Groups[2].Value, $p.Groups[3].Value
    $end   = '{0}-{1}-{2}' -f $p.Groups[4].Value, $p.Groups[5].Value, $p.Groups[6].Value
    $rows = @()
    foreach ($seg in ([regex]::Split($html, 'class="chart-item rank-data') | Select-Object -Skip 1)) {
        $rank   = [regex]::Match($seg, 'rank-container"><div class="top">\s*(\d+)\s*</div>')
        $artist = [regex]::Match($seg, 'row-container"><div class="top" title="([^"]*)"')
        $score  = [regex]::Match($seg, 'stat-container"><div class="left">\s*([\d,\.]+)\s*</div>')
        $aid    = [regex]::Match($seg, '/artist/([A-Za-z0-9]+)\.')
        if (-not ($rank.Success -and $artist.Success)) { continue }
        $rows += [pscustomobject]@{
            week = $weekLabel; period_start = $start; period_end = $end
            rank = [int]$rank.Groups[1].Value
            artist = ([System.Net.WebUtility]::HtmlDecode($artist.Groups[1].Value)).Trim()
            artist_id = $(if ($aid.Success) { $aid.Groups[1].Value } else { '' })
            score = $(if ($score.Success) { [double]($score.Groups[1].Value -replace ',', '') } else { '' })
            source = 'hanteo_social_weekly'; collected_at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        }
        if ($rows.Count -ge 20) { break }
    }
    return $rows
}

try { $html = Get-HanteoHtml $Base } catch { Write-Log "ERROR social fetch failed: $($_.Exception.Message)"; exit 1 }

$existing = @(Read-CsvSafe $SocialCsv)
$have = @{}; foreach ($r in $existing) { $have["$($r.period_start)|$($r.artist)"] = $r }

# Pages to read: current week, plus listed past weeks when -Backfill
$pages = @(@{ label = 'current'; html = $html })
if ($Backfill) {
    $weeks = @([regex]::Matches($html, 'social/weekly/(\d{4}-W\d{2})') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    foreach ($w in $weeks) {
        Start-Sleep -Milliseconds 800   # be polite to the site
        try { $pages += @{ label = $w; html = (Get-HanteoHtml "$Base/$w") } } catch { Write-Log "WARN social $w fetch failed" }
    }
}

$added = 0; $updated = 0
foreach ($pg in $pages) {
    $rows = @(Parse-Social $pg.html $pg.label)
    if (-not $rows.Count) { Write-Log "WARN social: no rows parsed for $($pg.label) (layout changed?)"; continue }
    foreach ($r in $rows) {
        $k = "$($r.period_start)|$($r.artist)"
        if ($r.week -eq 'current') {
            $d = [datetime]::ParseExact($r.period_start, 'yyyy-MM-dd', $null)
            $wk = [Globalization.CultureInfo]::InvariantCulture.Calendar.GetWeekOfYear($d, 'FirstFourDayWeek', 'Monday')
            $r.week = '{0}-W{1:D2}' -f $d.AddDays(3).Year, $wk
        }
        if (-not $have.ContainsKey($k)) { $have[$k] = $r; $added++ }
        elseif ($r.score -ne '' -and $have[$k].score -eq '') { $have[$k] = $r; $updated++ }
    }
}
if ($added -or $updated -or -not (Test-Path $SocialCsv)) {
    $all = @($have.Values | Sort-Object period_start, { [int]$_.rank })
    Write-CsvUtf8 $all $SocialCsv
}
Write-Log "OK social: $added new row(s), $updated updated, pages read=$($pages.Count)"
