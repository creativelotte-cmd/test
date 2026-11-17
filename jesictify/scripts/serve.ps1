# Minimal static file server for previewing web/ at http://localhost:8765/ (no Python/Node needed)
param([int]$Port = 8765)
. (Join-Path $PSScriptRoot 'common.ps1')

$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'; '.json' = 'application/json; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.csv' = 'text/csv; charset=utf-8' }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Output "Serving $WebDir at http://localhost:$Port/"
$webRoot = [System.IO.Path]::GetFullPath($WebDir)
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
    $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ($rel -eq '') { $rel = 'index.html' }
    $path = [System.IO.Path]::GetFullPath((Join-Path $webRoot $rel))
    if ($path.StartsWith($webRoot) -and (Test-Path $path -PathType Leaf)) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $ext = [System.IO.Path]::GetExtension($path).ToLower()
        $ctx.Response.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
        $ctx.Response.Headers.Add('Cache-Control', 'no-store')
        $ctx.Response.ContentLength64 = $bytes.Length
        if ($ctx.Request.HttpMethod -ne 'HEAD') { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) }
    } else {
        $ctx.Response.StatusCode = 404
    }
    } catch { Write-Output "WARN $($_.Exception.Message)" }
    try { $ctx.Response.Close() } catch {}
}
