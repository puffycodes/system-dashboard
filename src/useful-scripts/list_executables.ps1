<#
.SYNOPSIS
    Lists the executable files on the local disks (name, directory, size,
    last modified time and category), tagged with the host name and
    current timestamp.

.DESCRIPTION
    Searches every fixed (local) drive for executable files. Each file's
    category comes from its extension:

      Executable   Programs: .exe .com .scr
      Library      Dynamic libraries: .dll .ocx
      Script       .bat .cmd .ps1 .vbs .vbe .js .jse .wsf .wsh
      Installer    .msi .msp .msix .msixbundle .appx .appxbundle
      Other        Any other extension in PATHEXT, such as .msc and .cpl

    Only executables are listed by default; choose others with -Category. Folders that can't be read are skipped, so run it as
    administrator to see everything. Junctions and symbolic links to folders
    are not followed, so no folder is searched twice.
    See docs/spec/list_executables.md.

.PARAMETER Format
    Output format: text (default), csv, json or html.

.PARAMETER OutFile
    Optional file to write to. If omitted, output goes to stdout.

.PARAMETER Path
    Folders to search instead of the local drives.

.PARAMETER AllDrives
    Also search removable, network and other drives that are ready, not only
    the local (fixed) ones. Ignored with -Path.

.PARAMETER Category
    The categories to list: any of Executable, Library, Script, Installer
    and Other. Default: Executable

.PARAMETER NoHostTag
    Leave out the host name and timestamp.

.EXAMPLE
    .\list_executables.ps1
    .\list_executables.ps1 -Format csv -OutFile executables.csv
    .\list_executables.ps1 -Path 'C:\Program Files', D:\Tools
    .\list_executables.ps1 -Category Executable, Library, Script, Installer, Other
    .\list_executables.ps1 -Category Executable, Library
    .\list_executables.ps1 -Category Script
    .\list_executables.ps1 -NoHostTag
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile,

    [string[]]$Path,

    [switch]$AllDrives,

    [ValidateSet('Executable', 'Library', 'Script', 'Installer', 'Other')]
    [string[]]$Category = @('Executable'),

    [switch]$NoHostTag
)

$ErrorActionPreference = 'Stop'

# ISO 8601, local time with its time-zone offset: when the search started,
# as the dashboard does
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'

if (-not $Path) {
    $Path = @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and ($AllDrives -or $_.DriveType -eq 'Fixed')
    } | ForEach-Object { $_.RootDirectory.FullName })
}

# The category of each extension (hashtable keys are case-insensitive)
$categories = @{}
foreach ($ext in '.exe', '.com', '.scr') { $categories[$ext] = 'Executable' }
foreach ($ext in '.dll', '.ocx') { $categories[$ext] = 'Library' }
foreach ($ext in '.bat', '.cmd', '.ps1', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh') { $categories[$ext] = 'Script' }
foreach ($ext in '.msi', '.msp', '.msix', '.msixbundle', '.appx', '.appxbundle') { $categories[$ext] = 'Installer' }
# Other: whatever else Windows runs without its extension being typed
foreach ($ext in "$env:PATHEXT".Split(';')) {
    if ($ext -match '^\.\w+$' -and -not $categories.ContainsKey($ext)) { $categories[$ext.ToLowerInvariant()] = 'Other' }
}

# Only the extensions of the chosen categories are listed
$wanted = @{}
foreach ($ext in $categories.Keys) {
    if ($Category -contains $categories[$ext]) { $wanted[$ext] = $categories[$ext] }
}

$invariant = [Globalization.CultureInfo]::InvariantCulture
$files = New-Object System.Collections.Generic.List[object]

# Walk each folder tree with an explicit stack, so a folder that can't be
# read is skipped instead of stopping the search
$stack = New-Object 'System.Collections.Generic.Stack[IO.DirectoryInfo]'
foreach ($root in $Path) {
    $stack.Push([IO.DirectoryInfo]::new((Resolve-Path -LiteralPath $root).ProviderPath))
}

while ($stack.Count) {
    $dir = $stack.Pop()
    Write-Verbose "Searching $($dir.FullName)"
    try {
        foreach ($entry in $dir.EnumerateFileSystemInfos()) {
            if ($entry -is [IO.DirectoryInfo]) {
                # Junctions and folder symlinks lead to folders searched elsewhere
                if (-not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($entry) }
            } elseif ($wanted.ContainsKey($entry.Extension)) {
                $files.Add([pscustomobject]@{
                    Name      = $entry.Name
                    Directory = $entry.DirectoryName
                    Size      = $entry.Length
                    # ISO 8601, local time with its time-zone offset
                    Modified  = $entry.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:sszzz', $invariant)
                    Category  = $wanted[$entry.Extension]
                })
            }
        }
    } catch [UnauthorizedAccessException], [IO.IOException], [Security.SecurityException] {
        # Unreadable folder (e.g. System Volume Information) or path too long: skip it
    }
}

# Overlapping -Path folders would list a file twice; keep one of each
$files = @($files | Sort-Object -Property Directory, Name -Unique)

if ($files.Count -eq 0) {
    Write-Error 'No executable files found.'
    exit 1
}

$hostName = $env:COMPUTERNAME

switch ($Format) {
    'text' {
        $output = $files | Format-Table -AutoSize | Out-String -Width 4096
        $output = $output.Trim()
        if (-not $NoHostTag) {
            $output = "Host Name: $hostName`r`nTimestamp: $timestamp`r`n`r`n$output"
        }
    }
    'csv' {
        # One table only, so the host tag goes in extra columns on each row
        $rows = if ($NoHostTag) { $files } else {
            $files | Select-Object @{ n = 'HostName'; e = { $hostName } },
                @{ n = 'Timestamp'; e = { $timestamp } }, Name, Directory, Size, Modified, Category
        }
        $output = $rows | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        if ($NoHostTag) {
            # -InputObject keeps a one-item list as a JSON array
            $output = ConvertTo-Json -InputObject $files
        } else {
            $output = ConvertTo-Json -Depth 3 -InputObject ([pscustomobject]@{
                HostName    = $hostName
                Timestamp   = $timestamp
                Executables = [object[]]$files
            })
        }
    }
    'html' {
        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }
        if ($NoHostTag) {
            $title = 'Executable files'
            $info = ''
        } else {
            $title = "Executable files on $(& $enc $hostName)"
            $info = "<table><tr><th>Host Name</th><td>$(& $enc $hostName)</td></tr>" +
                "<tr><th>Timestamp</th><td>$(& $enc $timestamp)</td></tr></table>"
        }
        $output = $files | ConvertTo-Html -Title $title `
            -PreContent "<h1>$title</h1>$info<p>$($files.Count) files</p>"
    }
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved $($files.Count) files to: $((Resolve-Path $OutFile).Path)"
} else {
    $output
}
