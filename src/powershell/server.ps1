<#
.SYNOPSIS
    Serves the system dashboard on http://localhost:<Port>/.

.DESCRIPTION
    A small HTTP server built on System.Net.HttpListener, so it runs on a stock
    Windows PowerShell 5.1 with nothing installed. It serves the static UI in
    .\www and a JSON API backed by .\modules\SystemDashboard.psm1.

    It listens on localhost only: the API exposes machine details and has no
    authentication. Press Ctrl+C to stop.

    Routes:
        GET /               -> www/index.html
        GET /<file>         -> static file from www/
        GET /api/software   -> { computerName, generatedAt, items: [{ Name, Version }] }

.PARAMETER Port
    Port to listen on. Default 8080.

.PARAMETER Open
    Open the dashboard in the default browser once the server starts.

.PARAMETER Help
    Show this help and exit without starting the server.

.EXAMPLE
    .\server.ps1 -Open
    .\server.ps1 -Help
    powershell -ExecutionPolicy Bypass -File .\server.ps1 -Port 9000
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8080,

    [switch]$Open,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    return
}

Import-Module (Join-Path $PSScriptRoot 'modules\SystemDashboard.psm1') -Force

$wwwRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'www'))

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
}

function Send-Response {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$ContentType = 'text/plain; charset=utf-8',
        [byte[]]$Body
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers['Cache-Control'] = 'no-store'
    if ($Body) {
        $Response.ContentLength64 = $Body.Length
        $Response.OutputStream.Write($Body, 0, $Body.Length)
    }
    $Response.Close()
}

function Send-Json {
    param([System.Net.HttpListenerResponse]$Response, $Data, [int]$StatusCode = 200)
    $json = ConvertTo-Json -InputObject $Data -Depth 5 -Compress
    Send-Response $Response $StatusCode 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($json))
}

function Send-Text {
    param([System.Net.HttpListenerResponse]$Response, [int]$StatusCode, [string]$Text)
    Send-Response $Response $StatusCode 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Send-StaticFile {
    param([System.Net.HttpListenerResponse]$Response, [string]$UrlPath)

    $relative = [Uri]::UnescapeDataString($UrlPath).TrimStart('/')
    if (-not $relative) { $relative = 'index.html' }

    # Resolve and make sure the result stays inside www/ (blocks ../ traversal)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $wwwRoot $relative))
    $insideRoot = $fullPath.StartsWith($wwwRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    if (-not $insideRoot -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        Send-Text $Response 404 'Not found'
        return
    }

    $type = $contentTypes[[IO.Path]::GetExtension($fullPath).ToLowerInvariant()]
    if (-not $type) { $type = 'application/octet-stream' }
    Send-Response $Response 200 $type ([IO.File]::ReadAllBytes($fullPath))
}

function Invoke-Request {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath

    try {
        if ($request.HttpMethod -ne 'GET') {
            Send-Text $response 405 'Method not allowed'
        } elseif ($path -eq '/api/software') {
            Send-Json $response ([ordered]@{
                computerName = $env:COMPUTERNAME
                generatedAt  = (Get-Date).ToString('o')
                items        = @(Get-InstalledSoftware)
            })
        } elseif ($path.StartsWith('/api/')) {
            Send-Json $response @{ error = "Unknown endpoint: $path" } 404
        } else {
            Send-StaticFile $response $path
        }
        $status = $response.StatusCode
    } catch {
        $status = 500
        Write-Warning "$($request.HttpMethod) $path failed: $_"
        try { Send-Json $response @{ error = "$_" } 500 } catch { }
    }

    Write-Host ('{0:HH:mm:ss} {1} {2} {3}' -f (Get-Date), $request.HttpMethod, $path, $status)
}

$url = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)

try {
    $listener.Start()
} catch {
    throw "Could not listen on $url. Is the port already in use? Try -Port <other>. ($($_.Exception.Message))"
}

Write-Host "System dashboard running at $url (Ctrl+C to stop)"
if ($Open) { Start-Process $url }

try {
    while ($listener.IsListening) {
        # Wait in short slices instead of a blocking GetContext() so Ctrl+C is handled
        $pending = $listener.GetContextAsync()
        while (-not $pending.AsyncWaitHandle.WaitOne(500)) { }
        Invoke-Request $pending.GetAwaiter().GetResult()
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host 'Server stopped.'
}
