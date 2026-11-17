# Asks for a YouTube Data API v3 key, TESTS it right away (videos.list, 1 quota unit),
# and only when YouTube accepts it saves it as the user environment variable YOUTUBE_API_KEY.
# Run it yourself in a PowerShell window; the key is never printed.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

while ($true) {
    $secure = Read-Host 'YouTube Data API key (paste, it stays hidden)' -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)).Trim()
    if (-not $key) { Write-Output 'Empty value, try again.'; continue }
    Write-Output ("Testing... (key {0} chars)" -f $key.Length)
    try {
        $r = Invoke-RestMethod -Uri ("https://www.googleapis.com/youtube/v3/videos?part=statistics&id=jNQXAC9IVRw&key=" + $key) -TimeoutSec 30
        if (-not $r.items) { throw 'empty response' }
    } catch {
        $detail = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Output "FAILED: YouTube rejected this key. $detail"
        Write-Output 'Check: YouTube Data API v3 must be ENABLED in the same Google Cloud project as the key.'
        Write-Output ''
        continue
    }
    [Environment]::SetEnvironmentVariable('YOUTUBE_API_KEY', $key, 'User')
    Write-Output 'SUCCESS: YouTube accepted the key and it is saved. You can close this window.'
    break
}
