<#
.SYNOPSIS
    Lists the information that identifies this machine: host name, IP
    addresses and current timestamp.

.DESCRIPTION
    The host name is the same as in list_installed_software.ps1 and
    list_executables.ps1, so their files can be matched to this host.
    See docs/spec/list_host_information.md.

.PARAMETER Format
    Output format: text (default), csv, json or html.

.PARAMETER OutFile
    Optional file to write to. If omitted, output goes to stdout.

.EXAMPLE
    .\list_host_information.ps1
    .\list_host_information.ps1 -Format json -OutFile host_information.json
#>
[CmdletBinding()]
param(
    [ValidateSet('text', 'csv', 'json', 'html')]
    [string]$Format = 'text',

    [string]$OutFile
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

$hostName = $env:COMPUTERNAME
# @() keeps none or one address as an array
$ipAddress = @(Get-IPAddress)
$ipText = if ($ipAddress.Count) { $ipAddress -join ', ' } else { 'N/A' }
# ISO 8601, local time with its time-zone offset
$timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'

switch ($Format) {
    'text' {
        $output = "Host Name:    $hostName`r`nIP Addresses: $ipText`r`nTimestamp:    $timestamp"
    }
    'csv' {
        $output = [pscustomobject]@{
            HostName    = $hostName
            IPAddresses = $ipText
            Timestamp   = $timestamp
        } | ConvertTo-Csv -NoTypeInformation
    }
    'json' {
        $output = ConvertTo-Json -InputObject ([pscustomobject]@{
            HostName    = $hostName
            IPAddresses = [object[]]$ipAddress
            Timestamp   = $timestamp
        })
    }
    'html' {
        $enc = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }
        $title = "Host information for $(& $enc $hostName)"
        $output = "<!DOCTYPE html>`r`n" +
            "<html><head><meta charset=`"utf-8`"><title>$title</title></head><body>`r`n" +
            "<h1>$title</h1>`r`n" +
            "<table>`r`n" +
            "<tr><th>Field</th><th>Value</th></tr>`r`n" +
            "<tr><td>Host Name</td><td>$(& $enc $hostName)</td></tr>`r`n" +
            "<tr><td>IP Addresses</td><td>$(& $enc $ipText)</td></tr>`r`n" +
            "<tr><td>Timestamp</td><td>$(& $enc $timestamp)</td></tr>`r`n" +
            "</table>`r`n" +
            '</body></html>'
    }
}

if ($OutFile) {
    $output | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Saved host information to: $((Resolve-Path $OutFile).Path)"
} else {
    $output
}
