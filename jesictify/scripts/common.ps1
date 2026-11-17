# Shared paths and helpers for Eumwon Daily (ASCII only: PowerShell 5.1 reads BOM-less .ps1 as ANSI)
$ErrorActionPreference = 'Stop'

$Root      = Split-Path -Parent $PSScriptRoot
$DataDir   = Join-Path $Root 'data'
$WebDir    = Join-Path $Root 'web'
$LogDir    = Join-Path $Root 'logs'
foreach ($d in @($DataDir, $WebDir, $LogDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

$ChartCsv   = Join-Path $DataDir 'chart_snapshots.csv'
$ArtistsCsv = Join-Path $DataDir 'artists.csv'
$TrendsCsv  = Join-Path $DataDir 'search_trends.csv'
$JsonOut    = Join-Path $DataDir 'eumwon-daily.json'
$JsOut      = Join-Path $WebDir  'data.js'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Read-CsvSafe([string]$Path) {
    if (Test-Path $Path) { return @(Import-Csv -Path $Path -Encoding UTF8) }
    return @()
}

function Write-CsvUtf8([object[]]$Rows, [string]$Path) {
    # UTF-8 without BOM so Excel-free tools (and Claude) read it cleanly
    $lines = $Rows | ConvertTo-Csv -NoTypeInformation
    Write-Utf8File $Path (($lines -join "`r`n") + "`r`n")
}

function Clean-Keyword([string]$s) {
    # drop "(...)" / "[...]" parts: "Kim(KIM)" -> "Kim", "Song (Feat. X)" -> "Song"
    $t = [regex]::Replace($s, '\s*[\(\[][^\)\]]*[\)\]]', '')
    $t = [regex]::Replace($t, '\s+', ' ').Trim()
    if ($t) { return $t } else { return $s.Trim() }
}

# Search targets = every artist and every song in the latest chart snapshot
function Get-SearchTargets {
    $chart = @(Read-CsvSafe $ChartCsv)
    if (-not $chart.Count) { return @() }
    $latestTime = ($chart | Sort-Object chart_time -Descending | Select-Object -First 1).chart_time
    $kwMap = @{}; foreach ($a in @(Read-CsvSafe $ArtistsCsv)) { $kwMap[$a.artist] = $a.search_keyword }
    $out = @(); $seen = @{}
    foreach ($e in @($chart | Where-Object { $_.chart_time -eq $latestTime } | Sort-Object { [int]$_.rank })) {
        $ak = Clean-Keyword $(if ($kwMap[$e.artist]) { $kwMap[$e.artist] } else { $e.artist })
        if (-not $seen.ContainsKey("A|$($e.artist)")) {
            $seen["A|$($e.artist)"] = $true
            $out += [pscustomobject]@{ target_type = 'artist'; artist = $e.artist; title = ''; keyword = $ak }
        }
        if (-not $seen.ContainsKey("S|$($e.artist)|$($e.title)")) {
            $seen["S|$($e.artist)|$($e.title)"] = $true
            $out += [pscustomobject]@{ target_type = 'song'; artist = $e.artist; title = $e.title; keyword = "$ak $(Clean-Keyword $e.title)" }
        }
    }
    return $out
}

# GET a public Hanteo chart page and decode it as UTF-8 (PS 5.1 may otherwise mis-decode Korean)
function Get-HanteoHtml([string]$Url) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 `
        -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) EumwonDaily/1.0'
    $bytes = New-Object byte[] $resp.RawContentStream.Length
    $resp.RawContentStream.Position = 0
    [void]$resp.RawContentStream.Read($bytes, 0, $bytes.Length)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path (Join-Path $LogDir 'collector.log') -Value $line -Encoding UTF8
    Write-Output $line
}
