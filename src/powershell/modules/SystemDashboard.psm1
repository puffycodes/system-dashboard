# Data collectors for the system dashboard. Each exported function returns
# plain objects; server.ps1 turns them into JSON for the web UI.

function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Lists installed software (name + version).

    .DESCRIPTION
        Same source and filtering as src/useful-scripts/list_installed_software.ps1: the registry
        Uninstall keys used by "Programs and Features", skipping entries without
        a DisplayName, system components, and updates/hotfixes attached to a
        parent product. See docs/spec/list_installed_software.md.
    #>
    [CmdletBinding()]
    param()

    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $software = foreach ($key in $uninstallKeys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -and
            $_.SystemComponent -ne 1 -and
            -not $_.ParentKeyName -and
            $_.ReleaseType -notin @('Update', 'Hotfix', 'Security Update')
        } | ForEach-Object {
            $version = if ($_.DisplayVersion) { "$($_.DisplayVersion)".Trim() } else { 'N/A' }
            [pscustomobject]@{
                Name    = "$($_.DisplayName)".Trim()
                Version = $version
            }
        }
    }

    # Same app can appear in multiple hives; keep one entry per name + version
    @($software | Sort-Object -Property Name, Version -Unique)
}

function Get-IPAddress {
    <#
    .SYNOPSIS
        Lists the machine's IP addresses, IPv4 first.

    .DESCRIPTION
        Same as src/useful-scripts/list_host_information.ps1: addresses of
        the interfaces that are up, skipping loopback and link-local addresses.
        See docs/spec/list_host_information.md.
    #>
    [CmdletBinding()]
    param()

    $addresses = foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne 'Up' -or $nic.NetworkInterfaceType -eq 'Loopback') { continue }
        foreach ($unicast in $nic.GetIPProperties().UnicastAddresses) {
            $ip = $unicast.Address
            if ([System.Net.IPAddress]::IsLoopback($ip) -or $ip.IsIPv6LinkLocal -or
                $ip.ToString().StartsWith('169.254.')) { continue }
            $ip
        }
    }
    $v4 = $addresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' }
    $v6 = $addresses | Where-Object { $_.AddressFamily -ne 'InterNetwork' }
    @(@($v4) + @($v6) | ForEach-Object { $_.ToString() } | Select-Object -Unique)
}

function Get-Executable {
    <#
    .SYNOPSIS
        Lists the executable files on the fixed (local) drives.

    .DESCRIPTION
        Same search and categories as src/useful-scripts/list_executables.ps1:
        each file's category comes from its extension, folders that can't be
        read are skipped, and junctions and symbolic links to folders are not
        followed. Sorted by directory, then name. See
        docs/spec/list_executables.md.

    .PARAMETER Category
        The categories to list: any of Executable, Library, Script, Installer
        and Other.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Executable', 'Library', 'Script', 'Installer', 'Other')]
        [string[]]$Category = @('Executable')
    )

    # The category of each extension (hashtable keys are case-insensitive)
    $categories = @{}
    foreach ($ext in '.exe', '.com', '.scr') { $categories[$ext] = 'Executable' }
    foreach ($ext in '.dll', '.ocx') { $categories[$ext] = 'Library' }
    foreach ($ext in '.bat', '.cmd', '.ps1', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh') { $categories[$ext] = 'Script' }
    foreach ($ext in '.msi', '.msp', '.msix', '.msixbundle', '.appx', '.appxbundle') { $categories[$ext] = 'Installer' }
    # Other: whatever else Windows runs without its extension being typed
    foreach ($ext in "$env:PATHEXT".Split(';')) {
        if ($ext -match '^\.\w+$' -and -not $categories.ContainsKey($ext)) { $categories[$ext] = 'Other' }
    }

    $wanted = @{}
    foreach ($ext in $categories.Keys) {
        if ($Category -contains $categories[$ext]) { $wanted[$ext] = $categories[$ext] }
    }

    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $files = New-Object System.Collections.Generic.List[object]

    # Walk each drive with an explicit stack, so a folder that can't be read
    # is skipped instead of stopping the search
    $stack = New-Object 'System.Collections.Generic.Stack[IO.DirectoryInfo]'
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if ($drive.IsReady -and $drive.DriveType -eq 'Fixed') { $stack.Push($drive.RootDirectory) }
    }

    while ($stack.Count) {
        $dir = $stack.Pop()
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

    @($files | Sort-Object -Property Directory, Name -Unique)
}

Export-ModuleMember -Function Get-InstalledSoftware, Get-IPAddress, Get-Executable
