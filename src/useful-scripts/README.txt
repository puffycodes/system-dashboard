USEFUL SCRIPTS
==============

Standalone scripts for inspecting a machine. Each runs on what the operating
system already ships with.

  List host information     The information that identifies the machine:
                            host name, IP addresses and timestamp.
                            list_host_information.ps1, .sh, .bat
  List installed software   The installed software: name and version,
                            tagged with the host name and timestamp.
                            list_installed_software.ps1, .sh, .bat
  List executables          The executable files on the local disks: name,
                            directory, size, last modified time and
                            category (executable, library, script,
                            installer or other), tagged with the host name
                            and timestamp.
                            list_executables.ps1, .sh

The examples below are run from this folder (src/useful-scripts/).

The lists are tagged with only the host name and timestamp, which identify
where and when they were read. Other information about the host, such as its
IP addresses, comes from list_host_information, whose host name matches the
lists', so their files can be matched to it.


LIST HOST INFORMATION
=====================

Scripts that list the information that identifies a machine: its host name,
IP addresses and the current timestamp.
Requirements: ../../docs/spec/list_host_information.md, and
../../docs/spec/macos.md for macOS

  Script                      Platform                    Formats                 Default output
  --------------------------  --------------------------  ----------------------  ----------------------
  list_host_information.ps1   Windows (PowerShell 5.1+)   text, csv, json, html   stdout
  list_host_information.sh    Linux, macOS (POSIX sh)     text, csv, json, html   stdout
  list_host_information.bat   Windows (cmd)               text only               host_information.txt

  .\list_host_information.ps1 [-Format text|csv|json|html] [-OutFile <path>]
  sh list_host_information.sh [-f text|csv|json|html] [-o output_file]
  list_host_information.bat [output_file]

The options are the same as for list_installed_software: -Format/-f and
-OutFile/-o, and -h for usage in .sh. The batch script writes to
output_file, or host_information.txt next to the script, and also prints the
information. Like the other .sh scripts, list_host_information.sh refuses to
be sourced.

Examples:

  .\list_host_information.ps1
  .\list_host_information.ps1 -Format json -OutFile host_information.json
  sh list_host_information.sh -f csv -o host_information.csv

Fields:

  Host Name      The computer name (uname -n on Linux and macOS), the same
                 as in the other scripts' host tag.
  IP Addresses   The addresses of the machine's active network interfaces,
                 IPv4 first (from ifconfig on macOS). Loopback and
                 link-local addresses (127.x.x.x, ::1, 169.254.x.x, fe80::)
                 are skipped. Shown as N/A if there are none.
  Timestamp      When the information was read, in ISO 8601 local time with
                 its time-zone offset (e.g. 2026-11-12T10:54:59+08:00). The
                 batch script uses the system's date and time format
                 instead.

Output formats:

  text   "Host Name:", "IP Addresses:" and "Timestamp:" lines
  csv    Header "HostName","IPAddresses","Timestamp" and one row, all fields
         quoted
  json   Object {"HostName": ..., "IPAddresses": [...], "Timestamp": ...}
  html   Full page whose title names the host, with a Field / Value table

In text, csv and html, multiple IP addresses are separated by ", ". In json,
IPAddresses is always an array, empty when there are none.

Exit codes: 0 on success; 2 for an invalid option or format (.sh only. In
.ps1, an invalid -Format raises a parameter validation error.) For .sh, 1
when the script is sourced.


LIST INSTALLED SOFTWARE
=======================

Scripts that list the software installed on a machine, with each item's name
and version. By default they tag the list with the host name and current
timestamp.
Requirements: ../../docs/spec/list_installed_software.md, and
../../docs/spec/macos.md for macOS

  Script                        Platform                    Formats                 Default output
  ----------------------------  --------------------------  ----------------------  ------------------------
  list_installed_software.ps1   Windows (PowerShell 5.1+)   text, csv, json, html   stdout
  list_installed_software.sh    Linux, macOS (POSIX sh)     text, csv, json, html   stdout
  list_installed_software.bat   Windows (cmd)               text only               installed_software.txt

On Windows, use the PowerShell script. It implements the full spec and handles
special characters in names correctly. The batch script is kept for machines
where PowerShell isn't available.

The dashboards reproduce these scripts' lists entry for entry: src/powershell/
and src/go/ on Windows match the .ps1 script, and src/go/ on Linux and macOS
matches the .sh script. If you change what a script lists, update the
dashboards to match. Their System panel shows the same host name and IP
addresses as list_host_information.

The dashboards' Download button also writes the same text, csv, json and
html files as the .sh script, built by softwareFormats and executableFormats
in www/app.js. If you change an output format, change it there too, in both
UI copies.


POWERSHELL (WINDOWS)
--------------------

  .\list_installed_software.ps1 [-Format text|csv|json|html] [-OutFile <path>] [-NoHostTag]

  -Format      Output format: text (default), csv, json or html.
  -OutFile     File to write to (UTF-8). If omitted, output is printed.
  -NoHostTag   Leave out the host name and timestamp.

Examples:

  .\list_installed_software.ps1
  .\list_installed_software.ps1 -Format csv  -OutFile installed_software.csv
  .\list_installed_software.ps1 -Format json -OutFile installed_software.json
  .\list_installed_software.ps1 -Format html -OutFile installed_software.html
  .\list_installed_software.ps1 -NoHostTag

If the execution policy blocks the script, run it with:

  powershell -ExecutionPolicy Bypass -File .\list_installed_software.ps1 -Format csv

Help: Get-Help .\list_installed_software.ps1 -Full


SH (LINUX AND MACOS)
--------------------

  sh list_installed_software.sh [-f text|csv|json|html] [-o output_file] [-n]

  -f   Output format: text (default), csv, json or html.
  -o   File to write to. If omitted, output is printed.
  -n   Leave out the host name and timestamp.
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

It writes a "Name  |  Version" list, after the host name and timestamp, to
output_file. -n leaves out the host name and timestamp, and must come before
output_file. If you don't give a file, it writes installed_software.txt next
to the script. It also prints the list to the console.

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

macOS lists:

  - The apps (.app bundles) in /Applications and ~/Applications, and in
    their subfolders (e.g. /Applications/Utilities), but not apps inside
    other apps. The name is the app's name as Finder shows it (e.g. Google
    Chrome), and the version is its CFBundleShortVersionString, or
    CFBundleVersion if that is missing. The apps that come with macOS (e.g.
    Safari, Mail) are left out.
  - Homebrew formulae and casks, when Homebrew is installed: the same as
    "brew list --versions" and "brew list --cask --versions", read from
    Homebrew's Cellar and Caskroom folders in /opt/homebrew (Apple silicon)
    and /usr/local (Intel), so brew itself isn't run. If more than one
    version is installed, the latest is listed. An app installed as a cask
    can appear twice, by its app name and by its cask name.

In every script, a missing version is shown as N/A, and duplicate
name + version entries are listed once.


HOST TAG
--------

Unless turned off (-NoHostTag, or -n for .sh and .bat), the output also
gives:

  Host Name      The computer name (uname -n on Linux and macOS), as in
                 list_host_information.
  Timestamp      When the list was made, in ISO 8601 local time with its
                 time-zone offset (e.g. 2026-11-12T10:54:59+08:00). The
                 batch script uses the system's date and time format
                 instead.

The IP addresses are no longer in these files; use list_host_information for
them.


OUTPUT FORMATS
--------------

  text   Aligned Name / Version table
  csv    Header "Name","Version", all fields quoted
  json   Array of {"Name": ..., "Version": ...} objects
  html   Full page with a title, item count and a Name / Version table

With the host tag:

  text   "Host Name:" and "Timestamp:" lines, then a blank line, before the
         table
  csv    HostName and Timestamp columns before Name and Version, repeated on
         each row
  json   Object {"HostName": ..., "Timestamp": ..., "Software": [...]}, with
         the array under Software
  html   Title names the host, and a Host Name / Timestamp table comes before
         the item count


EXIT CODES
----------

  0   Success
  1   No installed software found. For .sh, also returned when the script
      is sourced.
  2   Invalid option or format (.sh only. In .ps1, an invalid -Format raises
      a parameter validation error.)


LIST EXECUTABLES
================

Scripts that list the executable files on a machine's local disks, with each
file's name, directory, size, last modified time and category. By default
they list only programs; dynamic libraries, scripts, installers and other
executable files are listed when you ask for them. Like
list_installed_software, they tag the list with the host name and timestamp
by default.
Requirements: ../../docs/spec/list_executables.md, and
../../docs/spec/macos.md for macOS

  Script                 Platform                    Formats                 Default output
  ---------------------  --------------------------  ----------------------  --------------
  list_executables.ps1   Windows (PowerShell 5.1+)   text, csv, json, html   stdout
  list_executables.sh    Linux, macOS (POSIX sh)     text, csv, json, html   stdout

Searching whole disks takes a while, often several minutes on Windows.
Folders that can't be read are skipped, so run the scripts as administrator
(Windows) or root (Linux and macOS) to see everything. On macOS, some folders
are protected even from root; see "macOS: Full Disk Access" in ../../README.md.


POWERSHELL (WINDOWS)
--------------------

  .\list_executables.ps1 [-Format text|csv|json|html] [-OutFile <path>]
                         [-Path <folder>[, ...]] [-AllDrives]
                         [-Category Executable|Library|Script|Installer|Other[, ...]]
                         [-NoHostTag]

  -Format      Output format: text (default), csv, json or html.
  -OutFile     File to write to (UTF-8). If omitted, output is printed.
  -Path        Folders to search instead of the local drives.
  -AllDrives   Also search removable, network and other drives that are
               ready. Ignored with -Path.
  -Category    The categories to list (see CATEGORIES): any of Executable,
               Library, Script, Installer and Other.
               Default: Executable
  -NoHostTag   Leave out the host name and timestamp.

Examples:

  .\list_executables.ps1 -Format csv -OutFile executables.csv
  .\list_executables.ps1 -Path 'C:\Program Files', D:\Tools
  .\list_executables.ps1 -Category Executable, Library, Script, Installer, Other -Format json -OutFile executables.json
  .\list_executables.ps1 -Category Executable, Library
  .\list_executables.ps1 -Category Script, Installer
  .\list_executables.ps1 -NoHostTag -Format csv -OutFile executables.csv

Help: Get-Help .\list_executables.ps1 -Full


SH (LINUX AND MACOS)
--------------------

  sh list_executables.sh [-f text|csv|json|html] [-o output_file] [-a] [-c categories] [-p folder]... [-n]

  -f   Output format: text (default), csv, json or html.
  -o   File to write to. If omitted, output is printed.
  -a   Also search network shares and other mounted filesystems, except
       virtual ones such as /proc and /sys on Linux and devfs on macOS.
  -c   The categories to list (see CATEGORIES), separated by commas: any of
       executable, library, script, installer and other, or all.
       Default: executable
  -p   Search this folder instead of the local disks or volumes. Repeat it
       for more folders.
  -n   Leave out the host name and timestamp.
  -h   Show usage.

Examples:

  sudo sh list_executables.sh -f csv -o executables.csv
  sh list_executables.sh -p /usr/local/bin -p /opt
  sh list_executables.sh -c all -f json -o executables.json
  sh list_executables.sh -c executable,library
  sh list_executables.sh -c script,installer
  sh list_executables.sh -n -f csv -o executables.csv

Like list_installed_software.sh, it refuses to be sourced. It works with GNU
or BusyBox tools on Linux, and with the BSD tools that macOS ships.


CATEGORIES
----------

Each file listed is in one category, shown in its Category field.

  Executable   Windows: programs (.exe .com .scr)
               Linux: an ELF program, i.e. a file with an execute bit that
               starts with the ELF signature, or that can't be read
               macOS: a Mach-O program, i.e. a file with an execute bit that
               starts with a Mach-O or universal binary signature, or that
               can't be read
  Library      Windows: dynamic libraries (.dll .ocx)
               Linux: a dynamic library, i.e. a file named *.so or *.so.*,
               with or without an execute bit
               macOS: a dynamic library, i.e. a file named *.dylib or *.so,
               with or without an execute bit, or a framework's binary with
               an execute bit (e.g. Foo.framework/Versions/A/Foo)
  Script       Windows: .bat .cmd .ps1 .vbs .vbe .js .jse .wsf .wsh
               Linux and macOS: a file with an execute bit that starts
               with #!
  Installer    Windows: .msi .msp .msix .msixbundle .appx .appxbundle
               Linux: a package or installer, i.e. a file named *.deb,
               *.rpm or *.run, with or without an execute bit
               macOS: a file named *.pkg, *.mpkg or *.dmg, with or without
               an execute bit
  Other        Windows: any other extension in PATHEXT, such as .msc and
               .cpl
               Linux: any other file with an execute bit
               macOS: any other file with an execute bit, including Java
               .class files, which start like a universal binary

Only Executable is listed by default. On Linux and macOS, Other is mostly
data files that happen to have an execute bit. On Windows, PATHEXT is the
list of extensions Windows runs without them being typed; if you add one
(e.g. .py), its files become Other.


WHAT IS SEARCHED
----------------

Windows: the fixed drives (C: and other internal disks). Junctions and
symbolic links to folders are not followed, so no folder is searched twice.

Linux: the filesystems on a /dev/ block device, plus ZFS, so network
mounts, tmpfs, /proc and, in WSL, the Windows drives under /mnt/ are left
out. Each filesystem is searched once, even if it's mounted in several
places, and the search never crosses into another filesystem, including from
a -p folder. Only regular files are listed: symbolic links aren't, but the
files they point to are.

macOS: the volumes that macOS marks as local, including external disks and
mounted disk images under /Volumes, so network shares are left out. macOS's
own support volumes (/System/Volumes/VM, Preboot, Update and so on) and Time
Machine snapshots are left out too. Files on the data volume are shown under
their usual paths (e.g. /Users/..., /Applications/...), not under
/System/Volumes/Data, and each file is listed once. As on Linux, the search
never crosses into another volume, and only regular files are listed: an app
bundle or installer package that is a folder isn't, but the files inside it
are. Some folders are protected by macOS's privacy controls, even from root;
see "macOS: Full Disk Access" in ../../README.md to include them.


FIELDS AND OUTPUT FORMATS
-------------------------

  Name        File name
  Directory   Full path of the folder the file is in
  Size        Size in bytes
  Modified    Last modified time, in ISO 8601 local time with its time-zone
              offset (e.g. 2026-11-12T10:54:59+08:00)
  Category    Executable, Library, Script, Installer or Other (see
              CATEGORIES above)

Files are sorted by directory, then name, and a file found twice (e.g. from
overlapping -Path folders) is listed once.

  text   Aligned Name / Directory / Size / Modified / Category table
  csv    Header "Name","Directory","Size","Modified","Category", all fields
         quoted
  json   Array of {"Name": ..., "Directory": ..., "Size": <number>,
         "Modified": ..., "Category": ...} objects
  html   Full page titled "Executable files", with the file count and a table

With the host tag (the default):

  text   "Host Name:" and "Timestamp:" lines, then a blank line, before the
         table
  csv    HostName and Timestamp columns before Name, repeated on each row
  json   Object {"HostName": ..., "Timestamp": ..., "Executables": [...]},
         with the array under Executables
  html   Title names the host ("Executable files on <host>"), and a
         Host Name / Timestamp table comes before the file count

The host tag's timestamp is when the search started, as in the dashboard.

With BusyBox, whose stat doesn't report time zones, Modified uses the
machine's current time-zone offset, which can be an hour off for files dated
on the other side of a daylight-saving change.


EXIT CODES
----------

  0   Success
  1   No executable files found. For .sh, also returned when the script is
      sourced.
  2   Invalid option, format, category or -p folder (.sh only. In .ps1, an
      invalid -Format or -Category, or a missing -Path folder, raises an
      error.)
