<#
.SYNOPSIS
    Lists the executable files on the local disks (name, directory, size,
    last modified time and category).

.DESCRIPTION
    Searches every fixed (local) drive for executable files. Each file's
    category comes from its extension:

      Executable   Programs: .exe .com .scr
      Library      Dynamic libraries: .dll .ocx
      Other        Scripts and installers: .bat .cmd .ps1 .vbs .js .wsf .msi .msp

    Executables and libraries are listed by default; choose others with
    -Category. Folders that can't be read are skipped, so run it as
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
    The categories to list: Executable, Library and/or Other.
    Default: Executable, Library

.EXAMPLE
    .\list_executables.ps1
    .\list_executables.ps1 -Format csv -OutFile executables.csv
    .\list_executables.ps1 -Path 'C:\Program Files', D:\Tools
    .\list_executables.ps1 -Category Executable, Library, Other
    .\list_executables.ps1 -Category Other
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile,

    [string[]]$Path,

    [switch]$AllDrives,

    [ValidateSet('Executable', 'Library', 'Other')]
    [string[]]$Category = @('Executable', 'Library')
)

$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and ($AllDrives -or $_.DriveType -eq 'Fixed')
    } | ForEach-Object { $_.RootDirectory.FullName })
}

# The category of each extension (hashtable keys are case-insensitive)
$categories = @{}
foreach ($ext in '.exe', '.com', '.scr') { $categories[$ext] = 'Executable' }
foreach ($ext in '.dll', '.ocx') { $categories[$ext] = 'Library' }
foreach ($ext in '.bat', '.cmd', '.ps1', '.vbs', '.js', '.wsf', '.msi', '.msp') { $categories[$ext] = 'Other' }

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

switch ($Format) {
    'text' {
        $output = $files | Format-Table -AutoSize | Out-String -Width 4096
        $output = $output.Trim()
    }
    'csv' {
        $output = $files | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        # -InputObject keeps a one-item list as a JSON array
        $output = ConvertTo-Json -InputObject $files
    }
    'html' {
        $output = $files | ConvertTo-Html -Title 'Executable files' `
            -PreContent "<h1>Executable files</h1><p>$($files.Count) files</p>"
    }
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved $($files.Count) files to: $((Resolve-Path $OutFile).Path)"
} else {
    $output
}
