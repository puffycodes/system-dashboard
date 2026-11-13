<#
.SYNOPSIS
    Lists installed software (name + version), tagged with the host name
    and current timestamp.

.DESCRIPTION
    Reads the same registry Uninstall keys that "Programs and Features" uses
    and applies the same filtering: entries without a DisplayName, system
    components, and updates/hotfixes attached to a parent product are skipped.
    The host's IP addresses are listed by list_host_information.ps1.
    See docs/spec/list_installed_software.md.

.PARAMETER Format
    Output format: text (default), csv, json or html.

.PARAMETER OutFile
    Optional file to write to. If omitted, output goes to stdout.

.PARAMETER NoHostTag
    Leave out the host name and timestamp.

.EXAMPLE
    .\list_installed_software.ps1
    .\list_installed_software.ps1 -Format csv -OutFile installed_software.csv
    .\list_installed_software.ps1 -NoHostTag
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile,

    [switch]$NoHostTag
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

if (-not $NoHostTag) {
    $hostName = $env:COMPUTERNAME
    # ISO 8601, local time with its time-zone offset
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
}

switch ($Format) {
    'text' {
        $output = $software | Format-Table -AutoSize | Out-String -Width 4096
        $output = $output.Trim()
        if (-not $NoHostTag) {
            $output = "Host Name: $hostName`r`nTimestamp: $timestamp`r`n`r`n$output"
        }
    }
    'csv' {
        # One table only, so the host tag goes in extra columns on each row
        $rows = if ($NoHostTag) { $software } else {
            $software | Select-Object @{ n = 'HostName'; e = { $hostName } },
                @{ n = 'Timestamp'; e = { $timestamp } }, Name, Version
        }
        $output = $rows | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        if ($NoHostTag) {
            # -InputObject keeps a one-item list as a JSON array
            $output = ConvertTo-Json -InputObject $software
        } else {
            $output = ConvertTo-Json -Depth 3 -InputObject ([pscustomobject]@{
                HostName  = $hostName
                Timestamp = $timestamp
                Software  = [object[]]$software
            })
        }
    }
    'html' {
        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }
        if ($NoHostTag) {
            $title = 'Installed software'
            $info = ''
        } else {
            $title = "Installed software on $(& $enc $hostName)"
            $info = "<table><tr><th>Host Name</th><td>$(& $enc $hostName)</td></tr>" +
                "<tr><th>Timestamp</th><td>$(& $enc $timestamp)</td></tr></table>"
        }
        $output = $software | ConvertTo-Html -Title $title `
            -PreContent "<h1>$title</h1>$info<p>$($software.Count) items</p>"
    }
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved $($software.Count) items to: $((Resolve-Path $OutFile).Path)"
} else {
    $output
}
