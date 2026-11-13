<#
.SYNOPSIS
    Packages the system dashboard for copying to target machines.

.DESCRIPTION
    Writes one archive per target to -OutDir, containing only the files the
    target needs (see "Copying the dashboard to another machine" in README.md):

        system-dashboard-<version>-powershell.zip      PowerShell version: start.cmd, server.ps1, modules\, www\
        system-dashboard-<version>-windows-amd64.zip   system-dashboard.exe
        system-dashboard-<version>-linux-amd64.tar.gz  system-dashboard-linux-amd64, marked executable
        system-dashboard-<version>-linux-arm64.tar.gz  system-dashboard-linux-arm64, marked executable
        system-dashboard-<version>-darwin-arm64.tar.gz system-dashboard-darwin-arm64, marked executable
        system-dashboard-<version>-darwin-amd64.tar.gz system-dashboard-darwin-amd64, marked executable
        SHA256SUMS                                     checksums, for sha256sum -c

    Each archive's files are in a folder named after the archive (e.g.
    system-dashboard-<version>-windows-amd64), so extracting it never mixes
    them with other files, even another of these packages.

    Each archive also has a README.txt on running that package, made from
    scripts\package-readme\<powershell|windows|linux|macos>.txt with the
    version (and the Linux or macOS binary's name) filled in. The Windows ones
    get CRLF endings.

    The macOS binaries for Apple silicon are signed ad hoc by Go's linker,
    which Apple silicon requires, so no Mac is needed to build them. They
    aren't signed with a Developer ID or notarized.

    The Go binaries are built after running the Go tests. Archives are made
    with Windows' built-in tar.exe (Windows 10 1803 or later), which also sets
    the executable bit on the Linux and macOS binaries. Earlier output of this script
    in -OutDir is replaced; other files there are left alone.

    Files are taken from the working tree, so uncommitted changes are included.
    If tracked files have uncommitted changes, the default version ends in "-dirty".

.PARAMETER Version
    Version used in the archive names, and reported by the Go binaries with
    -version and the PowerShell version with -Version (from a VERSION file
    added to its folder). Default: git describe --tags --always --dirty,
    or "dev" outside a git checkout.

.PARAMETER OutDir
    Output folder. Default: dist\ at the repo root.

.PARAMETER SkipGo
    Only package the PowerShell version, so Go isn't needed.

.EXAMPLE
    .\scripts\package.ps1
    .\scripts\package.ps1 -Version 1.0.0 -OutDir C:\temp\release
    .\scripts\package.ps1 -SkipGo
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutDir,
    [switch]$SkipGo
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$psSource = Join-Path $repo 'src\powershell'
$goSource = Join-Path $repo 'src\go'

$linuxTargets = @('amd64', 'arm64')
$macTargets = @('arm64', 'amd64')

function Invoke-Native {
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
}

function Get-DefaultVersion {
    try {
        $described = & git -C $repo describe --tags --always --dirty 2>$null
        if ($LASTEXITCODE -eq 0 -and $described) { return "$described".Trim() }
    } catch { }
    'dev'
}

function Write-PackageReadme {
    param([string]$Template, [string]$Dir, [string]$Binary, [switch]$Crlf)
    $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "package-readme\$Template.txt"))
    $text = $text.Replace("`r`n", "`n").Replace('@VERSION@', $Version).Replace('@BINARY@', $Binary)
    if ($Crlf) { $text = $text.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText((Join-Path $Dir 'README.txt'), $text)
}

function New-Zip {
    param([string]$ZipPath, [string]$FromDir, [string[]]$Entry)
    # tar.exe writes zip entries with / separators; Compress-Archive in
    # PowerShell 5.1 writes \, which breaks extraction on other systems
    Invoke-Native "Creating $(Split-Path -Leaf $ZipPath)" { tar.exe -a -c -f $ZipPath -C $FromDir @Entry }
}

function New-ExecutableTarGz {
    param([string]$TarPath, [string]$FromDir, [string]$Folder, [string]$FileName)
    # An mtree spec sets the modes explicitly; NTFS has no executable bit to copy.
    # The dir line steps into $Folder, so the files below it are stored inside it.
    $spec = Join-Path (Split-Path -Parent $FromDir) "$FileName.mtree"
    $owner = 'uid=0 gid=0 uname=root gname=root'
    [IO.File]::WriteAllText($spec,
        "#mtree`n" +
        "$Folder type=dir mode=0755 $owner`n" +
        "$FileName type=file mode=0755 $owner contents=$Folder/$FileName`n" +
        "README.txt type=file mode=0644 $owner contents=$Folder/README.txt`n" +
        "..`n")
    Push-Location $FromDir
    try {
        Invoke-Native "Creating $(Split-Path -Leaf $TarPath)" { tar.exe -c -z -f $TarPath "@$spec" }
    } finally {
        Pop-Location
    }
}

function Invoke-GoBuild {
    param([string]$GoOS, [string]$GoArch, [string]$OutFile)
    $names = 'GOOS', 'GOARCH', 'CGO_ENABLED'
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    try {
        $env:GOOS = $GoOS
        $env:GOARCH = $GoArch
        $env:CGO_ENABLED = '0'   # fully static, runs on any Linux distro; no C toolchain needed for macOS
        Invoke-Native "go build ($GoOS/$GoArch)" { go build -trimpath -ldflags "-s -w -X main.version=$Version" -o $OutFile . }
    } finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    }
}

# --- Setup ---------------------------------------------------------------

if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    throw 'tar.exe not found. It ships with Windows 10 version 1803 and later.'
}
if (-not $SkipGo -and -not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw 'Go not found. Install Go 1.20+ to build the binaries, or use -SkipGo to package only the PowerShell version.'
}

if (-not $Version) { $Version = Get-DefaultVersion }
$Version = $Version -replace '[^\w.+-]', '-'   # keep it safe in file names

if (-not $OutDir) { $OutDir = Join-Path $repo 'dist' }
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Remove earlier output of this script only
Get-ChildItem -LiteralPath $OutDir -File | Where-Object {
    $_.Name -eq 'SHA256SUMS' -or $_.Name -like 'system-dashboard-*.zip' -or $_.Name -like 'system-dashboard-*.tar.gz'
} | Remove-Item

$stage = Join-Path ([IO.Path]::GetTempPath()) ("system-dashboard-package-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null

$archives = New-Object System.Collections.Generic.List[string]

try {
    # --- PowerShell version ----------------------------------------------

    # Each archive's files go in a folder named after the archive
    $folder = "system-dashboard-$Version-powershell"

    Write-Host "Packaging the PowerShell version ($Version)"
    $psStage = Join-Path $stage 'powershell'
    $psDir = Join-Path $psStage $folder
    New-Item -ItemType Directory -Path $psDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $psSource 'start.cmd'), (Join-Path $psSource 'server.ps1') -Destination $psDir
    Copy-Item -LiteralPath (Join-Path $psSource 'modules'), (Join-Path $psSource 'www') -Destination $psDir -Recurse
    [IO.File]::WriteAllText((Join-Path $psDir 'VERSION'), "$Version`n")   # read by server.ps1 -Version
    Write-PackageReadme -Template powershell -Dir $psDir -Crlf

    $zip = Join-Path $OutDir "$folder.zip"
    New-Zip -ZipPath $zip -FromDir $psStage -Entry $folder
    $archives.Add($zip)

    # --- Go binaries -----------------------------------------------------

    if ($SkipGo) {
        Write-Host 'Skipping the Go binaries (-SkipGo)'
    } else {
        Push-Location $goSource
        try {
            Write-Host 'Running Go vet and tests'
            Invoke-Native 'go vet' { go vet ./... }
            Invoke-Native 'go test' { go test ./... }

            Write-Host 'Building windows/amd64'
            $folder = "system-dashboard-$Version-windows-amd64"
            $winStage = Join-Path $stage 'windows-amd64'
            $winDir = Join-Path $winStage $folder
            Invoke-GoBuild -GoOS windows -GoArch amd64 -OutFile (Join-Path $winDir 'system-dashboard.exe')
            Write-PackageReadme -Template windows -Dir $winDir -Crlf
            $zip = Join-Path $OutDir "$folder.zip"
            New-Zip -ZipPath $zip -FromDir $winStage -Entry $folder
            $archives.Add($zip)

            foreach ($arch in $linuxTargets) {
                Write-Host "Building linux/$arch"
                $name = "system-dashboard-linux-$arch"
                $folder = "system-dashboard-$Version-linux-$arch"
                $linuxStage = Join-Path $stage "linux-$arch"
                $linuxDir = Join-Path $linuxStage $folder
                Invoke-GoBuild -GoOS linux -GoArch $arch -OutFile (Join-Path $linuxDir $name)
                Write-PackageReadme -Template linux -Dir $linuxDir -Binary $name
                $tarGz = Join-Path $OutDir "$folder.tar.gz"
                New-ExecutableTarGz -TarPath $tarGz -FromDir $linuxStage -Folder $folder -FileName $name
                $archives.Add($tarGz)
            }

            foreach ($arch in $macTargets) {
                Write-Host "Building darwin/$arch"
                $name = "system-dashboard-darwin-$arch"
                $folder = "system-dashboard-$Version-darwin-$arch"
                $macStage = Join-Path $stage "darwin-$arch"
                $macDir = Join-Path $macStage $folder
                Invoke-GoBuild -GoOS darwin -GoArch $arch -OutFile (Join-Path $macDir $name)
                Write-PackageReadme -Template macos -Dir $macDir -Binary $name
                $tarGz = Join-Path $OutDir "$folder.tar.gz"
                New-ExecutableTarGz -TarPath $tarGz -FromDir $macStage -Folder $folder -FileName $name
                $archives.Add($tarGz)
            }
        } finally {
            Pop-Location
        }
    }

    # --- Checksums -------------------------------------------------------

    # sha256sum format with LF endings, so "sha256sum -c SHA256SUMS" works on Linux
    $sums = foreach ($archive in $archives) {
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant(), (Split-Path -Leaf $archive)
    }
    [IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS'), (($sums -join "`n") + "`n"))
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Packages in ${OutDir}:"
Get-ChildItem -LiteralPath $OutDir -File | Where-Object { $archives -contains $_.FullName -or $_.Name -eq 'SHA256SUMS' } |
    Format-Table Name, @{ Name = 'Size (KB)'; Expression = { [math]::Ceiling($_.Length / 1KB) }; Align = 'Right' } -AutoSize
