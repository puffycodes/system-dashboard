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

Export-ModuleMember -Function Get-InstalledSoftware
