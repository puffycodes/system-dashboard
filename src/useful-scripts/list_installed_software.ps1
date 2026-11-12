<#
.SYNOPSIS
    Lists installed software (name + version), with the host name, IP
    addresses and current timestamp.

.DESCRIPTION
    Reads the same registry Uninstall keys that "Programs and Features" uses
    and applies the same filtering: entries without a DisplayName, system
    components, and updates/hotfixes attached to a parent product are skipped.
    See docs/spec/list_installed_software.md.

.PARAMETER Format
    Output format: text (default), csv, json or html.

.PARAMETER OutFile
    Optional file to write to. If omitted, output goes to stdout.

.PARAMETER NoSystemInfo
    Leave out the host name, IP addresses and timestamp.

.EXAMPLE
    .\list_installed_software.ps1
    .\list_installed_software.ps1 -Format csv -OutFile installed_software.csv
    .\list_installed_software.ps1 -NoSystemInfo
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile,

    [switch]$NoSystemInfo
)

$ErrorActionPreference = 'Stop'

# Addresses of the interfaces that are up, IPv4 first. Loopback and
# link-local addresses are skipped, as they don't identify the machine.
function Get-IPAddress {
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

if (-not $NoSystemInfo) {
    $hostName = $env:COMPUTERNAME
    # @() keeps none or one address as an array
    $ipAddress = @(Get-IPAddress)
    $ipText = if ($ipAddress.Count) { $ipAddress -join ', ' } else { 'N/A' }
    # ISO 8601, local time with its time-zone offset
    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
}

switch ($Format) {
    'text' {
        $output = $software | Format-Table -AutoSize | Out-String -Width 4096
        $output = $output.Trim()
        if (-not $NoSystemInfo) {
            $output = "Host Name:    $hostName`r`nIP Addresses: $ipText`r`nTimestamp:    $timestamp`r`n`r`n$output"
        }
    }
    'csv' {
        # One table only, so the system info goes in extra columns on each row
        $rows = if ($NoSystemInfo) { $software } else {
            $software | Select-Object @{ n = 'HostName'; e = { $hostName } },
                @{ n = 'IPAddresses'; e = { $ipText } },
                @{ n = 'Timestamp'; e = { $timestamp } }, Name, Version
        }
        $output = $rows | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        if ($NoSystemInfo) {
            # -InputObject keeps a one-item list as a JSON array
            $output = ConvertTo-Json -InputObject $software
        } else {
            $output = ConvertTo-Json -Depth 3 -InputObject ([pscustomobject]@{
                HostName  = $hostName
                IPAddresses = [object[]]$ipAddress
                Timestamp = $timestamp
                Software  = [object[]]$software
            })
        }
    }
    'html' {
        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }
        if ($NoSystemInfo) {
            $title = 'Installed software'
            $info = ''
        } else {
            $title = "Installed software on $(& $enc $hostName)"
            $info = "<table><tr><th>Host Name</th><td>$(& $enc $hostName)</td></tr>" +
                "<tr><th>IP Addresses</th><td>$(& $enc $ipText)</td></tr>" +
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
