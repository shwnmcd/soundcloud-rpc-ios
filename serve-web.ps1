param(
    [int]$Port = 8080
)

$root = Join-Path $PSScriptRoot "web"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "SoundCloud RPC Web Companion running at http://localhost:$Port/" -ForegroundColor DarkYellow
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $reqPath = $context.Request.Url.AbsolutePath.TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($reqPath)) { $reqPath = "index.html" }

        $fullPath = Join-Path $root $reqPath
        if ((Test-Path $fullPath) -and !(Get-Item $fullPath).PSIsContainer) {
            $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
            $context.Response.ContentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $context.Response.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $context.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
        $context.Response.Close()
    }
} finally {
    $listener.Stop()
}
