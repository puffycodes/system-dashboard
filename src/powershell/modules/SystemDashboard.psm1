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
        Same as src/useful-scripts/list_installed_software.ps1: addresses of
        the interfaces that are up, skipping loopback and link-local addresses.
        See docs/spec/list_installed_software.md.
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

Export-ModuleMember -Function Get-InstalledSoftware, Get-IPAddress
