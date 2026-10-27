<#
.SYNOPSIS
    Builds the Go version of the dashboard as single executables.

.DESCRIPTION
    Builds one binary per -Target with the same flags as package.ps1, without
    running the tests or making archives. The web UI is embedded, so each
    binary can be copied and run on its own. Existing files are replaced.

        windows-amd64   src\go\system-dashboard.exe
        linux-amd64     src\go\system-dashboard-linux-amd64
        linux-arm64     src\go\system-dashboard-linux-arm64

    NTFS has no executable bit, so after copying a Linux binary to Linux, run
    chmod +x on it first. package.ps1 makes archives that keep the bit.

.PARAMETER Target
    One or more of windows-amd64, linux-amd64, linux-arm64, or "all".
    Default: windows-amd64.

.PARAMETER OutFile
    Path of the binary, instead of the default in src\go. Only with one target.

.EXAMPLE
    .\scripts\build.ps1
    .\scripts\build.ps1 -Target linux-amd64
    .\scripts\build.ps1 -Target windows-amd64, linux-arm64
    .\scripts\build.ps1 -Target all
    .\scripts\build.ps1 -OutFile C:\temp\system-dashboard.exe
#>
[CmdletBinding()]
param(
    [ValidateSet('windows-amd64', 'linux-amd64', 'linux-arm64', 'all')]
    [string[]]$Target = 'windows-amd64',
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$goSource = Join-Path $repo 'src\go'

$fileNames = [ordered]@{
    'windows-amd64' = 'system-dashboard.exe'
    'linux-amd64'   = 'system-dashboard-linux-amd64'
    'linux-arm64'   = 'system-dashboard-linux-arm64'
}

function Invoke-GoBuild {
    param([string]$GoOS, [string]$GoArch, [string]$OutFile)
    # Set the target explicitly, so GOOS/GOARCH left over in the session don't apply
    $names = 'GOOS', 'GOARCH', 'CGO_ENABLED'
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:GOOS = $GoOS
        $env:GOARCH = $GoArch
        $env:CGO_ENABLED = '0'   # fully static, runs on any Linux distro
        go build -trimpath -ldflags '-s -w' -o $OutFile .
        if ($LASTEXITCODE -ne 0) { throw "go build ($GoOS/$GoArch) failed (exit code $LASTEXITCODE)." }
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw 'Go not found. Install Go 1.20+ to build the executables.'
}

if ($Target -contains 'all') { $Target = @($fileNames.Keys) }
$Target = @($Target | Select-Object -Unique)
if ($OutFile -and $Target.Count -gt 1) {
    throw '-OutFile can only be used with a single -Target.'
}

$built = New-Object System.Collections.Generic.List[string]

Push-Location $goSource
try {
    foreach ($t in $Target) {
        $goOS, $goArch = $t -split '-'
        $out = if ($OutFile) { $OutFile } else { Join-Path $goSource $fileNames[$t] }
        $out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($out)
        Write-Host "Building $goOS/$goArch"
        Invoke-GoBuild -GoOS $goOS -GoArch $goArch -OutFile $out
        $built.Add($out)
    }
} finally {
    Pop-Location
}

Write-Host ''
foreach ($file in $built) {
    $size = [math]::Ceiling((Get-Item -LiteralPath $file).Length / 1KB)
    Write-Host "Built $file ($size KB)"
}
if ($Target | Where-Object { $_ -like 'linux-*' }) {
    Write-Host 'On Linux, run chmod +x on the binary before starting it.'
}
