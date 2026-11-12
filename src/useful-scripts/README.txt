LIST INSTALLED SOFTWARE
=======================

Scripts that list the software installed on a machine, with each item's name
and version. By default they also show the host name, IP addresses and
current timestamp.
Requirements: ../../docs/spec/list_installed_software.md

  Script                        Platform                    Formats                 Default output
  ----------------------------  --------------------------  ----------------------  ------------------------
  list_installed_software.ps1   Windows (PowerShell 5.1+)   text, csv, json, html   stdout
  list_installed_software.sh    Linux (any POSIX sh)        text, csv, json, html   stdout
  list_installed_software.bat   Windows (cmd)               text only               installed_software.txt

On Windows, use the PowerShell script. It implements the full spec and handles
special characters in names correctly. The batch script is kept for machines
where PowerShell isn't available.

The examples below are run from this folder (src/useful-scripts/).

The dashboards reproduce these scripts' lists entry for entry: src/powershell/
and src/go/ on Windows match the .ps1 script, and src/go/ on Linux matches the
.sh script. If you change what a script lists, update the dashboards to match.


POWERSHELL (WINDOWS)
--------------------

  .\list_installed_software.ps1 [-Format text|csv|json|html] [-OutFile <path>] [-NoSystemInfo]

  -Format         Output format: text (default), csv, json or html.
  -OutFile        File to write to (UTF-8). If omitted, output is printed.
  -NoSystemInfo   Leave out the host name, IP addresses and timestamp.

Examples:

  .\list_installed_software.ps1
  .\list_installed_software.ps1 -Format csv  -OutFile installed_software.csv
  .\list_installed_software.ps1 -Format json -OutFile installed_software.json
  .\list_installed_software.ps1 -Format html -OutFile installed_software.html
  .\list_installed_software.ps1 -NoSystemInfo

If the execution policy blocks the script, run it with:

  powershell -ExecutionPolicy Bypass -File .\list_installed_software.ps1 -Format csv

Help: Get-Help .\list_installed_software.ps1 -Full


SH (LINUX)
----------

  sh list_installed_software.sh [-f text|csv|json|html] [-o output_file] [-n]

  -f   Output format: text (default), csv, json or html.
  -o   File to write to. If omitted, output is printed.
  -n   Leave out the host name, IP addresses and timestamp.
  -h   Show usage.

Examples:

  sh list_installed_software.sh
  sh list_installed_software.sh -f csv  -o installed_software.csv
  sh list_installed_software.sh -f json -o installed_software.json
  ./list_installed_software.sh -f html -o installed_software.html
  sh list_installed_software.sh -n

NOTE: Run it, don't source it. "source list_installed_software.sh" or
". ./list_installed_software.sh" is refused, because the script's "set -eu"
would otherwise stay on in your shell and break things like prompt hooks
(e.g. "bash: Q_LOG_LEVEL: unbound variable").


BATCH (WINDOWS)
---------------

  list_installed_software.bat [-n] [output_file]

It writes a "Name  |  Version" list, after the host name, IP addresses and
timestamp, to output_file. -n leaves out the host name, IP addresses and
timestamp, and must come before output_file. If you don't give a file, it
writes installed_software.txt next to the script. It also prints the list to
the console.

Limitations: text output only. The timestamp is in the system's date and time
format, not ISO 8601. Names containing %, ^ or " may be mangled.


WHAT IS LISTED
--------------

Windows (both scripts) reads the same registry Uninstall keys that
"Programs and Features" uses:

  HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
  HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall
  HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall

Entries without a display name are skipped, and so are hidden system
components. The PowerShell script also skips updates and hotfixes listed under
a parent product. Microsoft Store (MSIX) apps are not included.

Linux lists packages from the first package manager it finds:

  dpkg     Debian, Ubuntu (fully installed packages only)
  rpm      Fedora, RHEL, SUSE
  pacman   Arch
  apk      Alpine

It also includes Flatpak apps and Snaps when they are present. Snaps are
skipped when the snap service isn't running, as in WSL without systemd. On
Linux the name is the package name (e.g. google-chrome-stable), and the list
includes libraries and other dependencies.

In every script, a missing version is shown as N/A, and duplicate
name + version entries are listed once.


SYSTEM INFORMATION
------------------

Unless turned off (-NoSystemInfo, or -n for .sh and .bat), the output also
gives:

  Host Name      The computer name (uname -n on Linux).
  IP Addresses   The addresses of the machine's active network interfaces,
                 IPv4 first. Loopback and link-local addresses (127.x.x.x,
                 ::1, 169.254.x.x, fe80::) are skipped. Shown as N/A if
                 there are none.
  Timestamp      When the list was made, in ISO 8601 local time with its
                 time-zone offset (e.g. 2026-11-12T10:54:59+08:00). The
                 batch script uses the system's date and time format
                 instead.


OUTPUT FORMATS
--------------

  text   Aligned Name / Version table
  csv    Header "Name","Version", all fields quoted
  json   Array of {"Name": ..., "Version": ...} objects
  html   Full page with a title, item count and a Name / Version table

With system information:

  text   "Host Name:", "IP Addresses:" and "Timestamp:" lines, then a blank
         line, before the table
  csv    HostName, IPAddresses and Timestamp columns before Name and Version,
         repeated on each row
  json   Object {"HostName": ..., "IPAddresses": [...], "Timestamp": ...,
         "Software": [...]}, with the array under Software
  html   Title names the host, and a Host Name / IP Addresses / Timestamp table
         comes before the item count

In text, csv and html, multiple IP addresses are separated by ", ". In json,
IPAddresses is always an array, empty when there are none.


EXIT CODES
----------

  0   Success
  1   No installed software found. For .sh, also returned when the script
      is sourced.
  2   Invalid option or format (.sh only. In .ps1, an invalid -Format raises
      a parameter validation error.)
