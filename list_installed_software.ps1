<#
.SYNOPSIS
    Lists installed software (name + version).

.DESCRIPTION
    Reads the same registry Uninstall keys that "Programs and Features" uses
    and applies the same filtering: entries without a DisplayName, system
    components, and updates/hotfixes attached to a parent product are skipped.
    See docs/spec/list_installed_software.md.

.PARAMETER Format
    Output format: text (default), csv, json or html.

.PARAMETER OutFile
    Optional file to write to. If omitted, output goes to stdout.

.EXAMPLE
    .\list_installed_software.ps1
    .\list_installed_software.ps1 -Format csv -OutFile installed_software.csv
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

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
$software = @($software | Sort-Object -Property Name, Version -Unique)

if ($software.Count -eq 0) {
    Write-Error 'No installed software found.'
    exit 1
}

switch ($Format) {
    'text' {
        $output = $software | Format-Table -AutoSize | Out-String -Width 4096
        $output = $output.Trim()
    }
    'csv' {
        $output = $software | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        # -InputObject keeps a one-item list as a JSON array
        $output = ConvertTo-Json -InputObject $software
    }
    'html' {
        $output = $software | ConvertTo-Html -Title "Installed software on $env:COMPUTERNAME" `
            -PreContent "<h1>Installed software on $env:COMPUTERNAME</h1><p>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &middot; $($software.Count) items</p>"
    }
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved $($software.Count) items to: $((Resolve-Path $OutFile).Path)"
} else {
    $output
}
