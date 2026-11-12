<#
.SYNOPSIS
    Lists the executable files on the local disks (name, directory, size and
    last modified time).

.DESCRIPTION
    Searches every fixed (local) drive for files with an executable extension.
    Folders that can't be read are skipped, so run it as administrator to see
    everything. Junctions and symbolic links to folders are not followed, so
    no folder is searched twice.
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

.PARAMETER Extension
    File extensions that count as executable, with or without the dot.
    Default: .exe .com .bat .cmd .ps1 .msi

.EXAMPLE
    .\list_executables.ps1
    .\list_executables.ps1 -Format csv -OutFile executables.csv
    .\list_executables.ps1 -Path 'C:\Program Files', D:\Tools
    .\list_executables.ps1 -Extension exe, dll
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile,

    [string[]]$Path,

    [switch]$AllDrives,

    [string[]]$Extension = @('.exe', '.com', '.bat', '.cmd', '.ps1', '.msi')
)

$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and ($AllDrives -or $_.DriveType -eq 'Fixed')
    } | ForEach-Object { $_.RootDirectory.FullName })
}

# Compared case-insensitively, with or without the leading dot
$extensions = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($ext in $Extension) { [void]$extensions.Add('.' + $ext.TrimStart('.')) }

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
            } elseif ($extensions.Contains($entry.Extension)) {
                $files.Add([pscustomobject]@{
                    Name      = $entry.Name
                    Directory = $entry.DirectoryName
                    Size      = $entry.Length
                    # ISO 8601, local time with its time-zone offset
                    Modified  = $entry.LastWriteTime.ToString('yyyy-MM-ddTHH:mm:sszzz', $invariant)
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
