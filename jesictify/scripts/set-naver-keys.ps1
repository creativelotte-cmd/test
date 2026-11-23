# Asks for the Naver DataLab Client ID / Secret, TESTS them against the API right away,
# and only when Naver accepts them saves them as user environment variables
# NAVER_CLIENT_ID / NAVER_CLIENT_SECRET (no file is written, so DRM cannot interfere).
# Run it yourself in a PowerShell window; the secret is never printed.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

while ($true) {
    $id = (Read-Host 'NAVER API HUB Client ID (Naver Cloud console > Application)').Trim()
    $secure = Read-Host 'Naver Client Secret (paste, it stays hidden)' -AsSecureString
    $secret = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)).Trim()
    if (-not $id -or -not $secret) { Write-Output 'Empty value, try again.'; continue }
    Write-Output ("Testing... (ID {0} chars, Secret {1} chars)" -f $id.Length, $secret.Length)

    $end = (Get-Date).Date.AddDays(-1).ToString('yyyy-MM-dd')
    $start = (Get-Date).Date.AddDays(-7).ToString('yyyy-MM-dd')
    $body = '{"startDate":"' + $start + '","endDate":"' + $end + '","timeUnit":"date","keywordGroups":[{"groupName":"test","keywords":["music"]}]}'
    try {
        Invoke-WebRequest -Uri 'https://naverapihub.apigw.ntruss.com/search-trend/v1/search' -Method Post -UseBasicParsing -TimeoutSec 30 `
            -Headers @{ 'X-NCP-APIGW-API-KEY-ID' = $id; 'X-NCP-APIGW-API-KEY' = $secret } `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    } catch {
        $detail = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-Output "FAILED: Naver rejected these keys. $detail"
        Write-Output 'Check: copy both values again from the Application auth info; the Search Trend API must be subscribed.'
        Write-Output ''
        continue
    }
    [Environment]::SetEnvironmentVariable('NAVER_CLIENT_ID', $id, 'User')
    [Environment]::SetEnvironmentVariable('NAVER_CLIENT_SECRET', $secret, 'User')
    Write-Output 'SUCCESS: Naver accepted the keys and they are saved. You can close this window.'
    break
}
