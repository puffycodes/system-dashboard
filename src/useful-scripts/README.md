# Useful Scripts

Standalone scripts for inspecting a machine. Each runs on what the operating system already ships with.

| Tool | Lists | Scripts |
|---|---|---|
| [List installed software](#list-installed-software) | The installed software: name and version, after the host name, IP addresses and timestamp | `list_installed_software.ps1`, `.sh`, `.bat` |
| [List executables](#list-executables) | The executable files on the local disks: name, directory, size and last modified time | `list_executables.ps1`, `.sh` |

The examples below are run from this folder (`src/useful-scripts/`).

## List installed software

Scripts that list the software installed on a machine, with each item's name and version. By default they also show the host name, IP addresses and current timestamp.
Requirements: [docs/spec/list_installed_software.md](../../docs/spec/list_installed_software.md).

| Script | Platform | Output formats | Default output |
|---|---|---|---|
| [`list_installed_software.ps1`](#powershell-windows) | Windows (PowerShell 5.1+) | text, csv, json, html | stdout |
| [`list_installed_software.sh`](#sh-linux) | Linux (any POSIX `sh`) | text, csv, json, html | stdout |
| [`list_installed_software.bat`](#batch-windows) | Windows (cmd) | text only | `installed_software.txt` |

On Windows, use the PowerShell script. It implements the full spec and handles special characters in names correctly. The batch script is kept for machines where PowerShell isn't available.

The dashboards reproduce these scripts' lists entry for entry: [`src/powershell/`](../powershell/) and [`src/go/`](../go/) on Windows match the `.ps1` script, and `src/go/` on Linux matches the `.sh` script. If you change what a script lists, update the dashboards to match. The dashboards' Download button also writes the same text, csv, json and html files as the `.sh` script, built by `downloadFormats` in `www/app.js`. If you change an output format, change it there too, in both UI copies.

### PowerShell (Windows)

```powershell
.\list_installed_software.ps1 [-Format text|csv|json|html] [-OutFile <path>] [-NoSystemInfo]
```

| Parameter | Default | Description |
|---|---|---|
| `-Format` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-OutFile` | *(stdout)* | File to write to (UTF-8). If omitted, output is printed. |
| `-NoSystemInfo` | *(off)* | Leave out the host name, IP addresses and timestamp. |

Examples:

```powershell
.\list_installed_software.ps1
.\list_installed_software.ps1 -Format csv  -OutFile installed_software.csv
.\list_installed_software.ps1 -Format json -OutFile installed_software.json
.\list_installed_software.ps1 -Format html -OutFile installed_software.html
.\list_installed_software.ps1 -NoSystemInfo
```

If the execution policy blocks the script, run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\list_installed_software.ps1 -Format csv
```

Help: `Get-Help .\list_installed_software.ps1 -Full`

### sh (Linux)

```sh
sh list_installed_software.sh [-f text|csv|json|html] [-o output_file] [-n]
```

| Option | Default | Description |
|---|---|---|
| `-f` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-o` | *(stdout)* | File to write to. If omitted, output is printed. |
| `-n` | | Leave out the host name, IP addresses and timestamp. |
| `-h` | | Show usage. |

Examples:

```sh
sh list_installed_software.sh
sh list_installed_software.sh -f csv  -o installed_software.csv
sh list_installed_software.sh -f json -o installed_software.json
./list_installed_software.sh -f html -o installed_software.html
sh list_installed_software.sh -n
```

> **Run it, don't source it.** `source list_installed_software.sh` or `. ./list_installed_software.sh` is refused, because the script's `set -eu` would otherwise stay on in your shell and break things like prompt hooks (e.g. `bash: Q_LOG_LEVEL: unbound variable`).

### Batch (Windows)

```bat
list_installed_software.bat [-n] [output_file]
```

It writes a `Name  |  Version` list, after the host name, IP addresses and timestamp, to `output_file`. `-n` leaves out the host name, IP addresses and timestamp, and must come before `output_file`. If you don't give a file, it writes `installed_software.txt` next to the script. It also prints the list to the console.

Limitations: text output only. The timestamp is in the system's date and time format, not ISO 8601. Names containing `%`, `^` or `"` may be mangled.

### What is listed

**Windows** (both scripts) reads the same registry Uninstall keys that *Programs and Features* uses:

- `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
- `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`
- `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`

Entries without a display name are skipped, and so are hidden system components. The PowerShell script also skips updates and hotfixes listed under a parent product. Microsoft Store (MSIX) apps are not included.

**Linux** lists packages from the first package manager it finds:

| Package manager | Distributions |
|---|---|
| `dpkg` | Debian, Ubuntu (fully installed packages only) |
| `rpm` | Fedora, RHEL, SUSE |
| `pacman` | Arch |
| `apk` | Alpine |

It also includes Flatpak apps and Snaps when they are present. Snaps are skipped when the snap service isn't running, as in WSL without systemd. On Linux the name is the package name (e.g. `google-chrome-stable`), and the list includes libraries and other dependencies.

In every script, a missing version is shown as `N/A`, and duplicate name + version entries are listed once.

### System information

Unless turned off (`-NoSystemInfo`, or `-n` for `.sh` and `.bat`), the output also gives:

- **Host Name**: the computer name (`uname -n` on Linux).
- **IP Addresses**: the addresses of the machine's active network interfaces, IPv4 first. Loopback and link-local addresses (`127.x.x.x`, `::1`, `169.254.x.x`, `fe80::`) are skipped. Shown as `N/A` if there are none.
- **Timestamp**: when the list was made, in ISO 8601 local time with its time-zone offset (e.g. `2026-11-12T10:54:59+08:00`). The batch script uses the system's date and time format instead.

### Output formats

| Format | Shape | With system information |
|---|---|---|
| `text` | Aligned `Name` / `Version` table | `Host Name:`, `IP Addresses:` and `Timestamp:` lines, then a blank line, before the table |
| `csv` | Header `"Name","Version"`, all fields quoted | `HostName`, `IPAddresses` and `Timestamp` columns before `Name` and `Version`, repeated on each row |
| `json` | Array of `{"Name": ..., "Version": ...}` objects | Object `{"HostName": ..., "IPAddresses": [...], "Timestamp": ..., "Software": [...]}`, with the array under `Software` |
| `html` | Full page with a title, item count and a `Name` / `Version` table | Title names the host, and a `Host Name` / `IP Addresses` / `Timestamp` table comes before the item count |

In text, csv and html, multiple IP addresses are separated by `, `. In json, `IPAddresses` is always an array, empty when there are none.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | No installed software found. For `.sh`, also returned when the script is sourced. |
| `2` | Invalid option or format (`.sh` only. In `.ps1`, an invalid `-Format` raises a parameter validation error.) |

## List executables

Scripts that list the executable files on a machine's local disks, with each file's name, directory, size, last modified time and category. By default they list only programs; dynamic libraries, scripts, installers and other executable files are listed when you ask for them.
Requirements: [docs/spec/list_executables.md](../../docs/spec/list_executables.md).

| Script | Platform | Output formats | Default output |
|---|---|---|---|
| [`list_executables.ps1`](#list_executablesps1-windows) | Windows (PowerShell 5.1+) | text, csv, json, html | stdout |
| [`list_executables.sh`](#list_executablessh-linux) | Linux (any POSIX `sh`) | text, csv, json, html | stdout |

Searching whole disks takes a while, often several minutes on Windows. Folders that can't be read are skipped, so run the scripts as administrator (Windows) or root (Linux) to see everything.

### list_executables.ps1 (Windows)

```powershell
.\list_executables.ps1 [-Format text|csv|json|html] [-OutFile <path>] [-Path <folder>[, ...]] [-AllDrives] [-Category Executable|Library|Script|Installer|Other[, ...]]
```

| Parameter | Default | Description |
|---|---|---|
| `-Format` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-OutFile` | *(stdout)* | File to write to (UTF-8). If omitted, output is printed. |
| `-Path` | *(local drives)* | Folders to search instead of the local drives. |
| `-AllDrives` | *(off)* | Also search removable, network and other drives that are ready. Ignored with `-Path`. |
| `-Category` | `Executable` | The [categories](#categories) to list: any of `Executable`, `Library`, `Script`, `Installer` and `Other`. |

Examples:

```powershell
.\list_executables.ps1 -Format csv -OutFile executables.csv
.\list_executables.ps1 -Path 'C:\Program Files', D:\Tools
.\list_executables.ps1 -Category Executable, Library, Script, Installer, Other -Format json -OutFile executables.json
.\list_executables.ps1 -Category Executable, Library
.\list_executables.ps1 -Category Script, Installer
```

Help: `Get-Help .\list_executables.ps1 -Full`

### list_executables.sh (Linux)

```sh
sh list_executables.sh [-f text|csv|json|html] [-o output_file] [-a] [-c categories] [-p folder]...
```

| Option | Default | Description |
|---|---|---|
| `-f` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-o` | *(stdout)* | File to write to. If omitted, output is printed. |
| `-a` | | Also search network and other mounted filesystems, except virtual ones such as `/proc` and `/sys`. |
| `-c` | `executable` | The [categories](#categories) to list, separated by commas: any of `executable`, `library`, `script`, `installer` and `other`, or `all`. |
| `-p` | *(local disks)* | Search this folder instead of the local disks. Repeat it for more folders. |
| `-h` | | Show usage. |

Examples:

```sh
sudo sh list_executables.sh -f csv -o executables.csv
sh list_executables.sh -p /usr/local/bin -p /opt
sh list_executables.sh -c all -f json -o executables.json
sh list_executables.sh -c executable,library
sh list_executables.sh -c script,installer
```

Like `list_installed_software.sh`, it refuses to be sourced. It works with GNU or BusyBox tools.

### Categories

Each file listed is in one category, shown in its `Category` field:

| Category | Windows (by extension) | Linux |
|---|---|---|
| `Executable` | Programs: `.exe`, `.com`, `.scr` | An ELF program: a file with an execute bit that starts with the ELF signature, or that can't be read |
| `Library` | Dynamic libraries: `.dll`, `.ocx` | A dynamic library: a file named `*.so` or `*.so.*`, with or without an execute bit |
| `Script` | `.bat`, `.cmd`, `.ps1`, `.vbs`, `.vbe`, `.js`, `.jse`, `.wsf`, `.wsh` | A file with an execute bit that starts with `#!` |
| `Installer` | `.msi`, `.msp`, `.msix`, `.msixbundle`, `.appx`, `.appxbundle` | A package or installer: a file named `*.deb`, `*.rpm` or `*.run`, with or without an execute bit |
| `Other` | Any other extension in `PATHEXT`, such as `.msc` and `.cpl` | Any other file with an execute bit |

Only `Executable` is listed by default. On Linux, `Other` is mostly data files that happen to have an execute bit. On Windows, `PATHEXT` is the list of extensions Windows runs without them being typed; if you add one (e.g. `.py`), its files become `Other`.

### What is searched

**Windows:** the fixed drives (`C:` and other internal disks). Junctions and symbolic links to folders are not followed, so no folder is searched twice.

**Linux:** the filesystems on a `/dev/` block device, plus ZFS, so network mounts, `tmpfs`, `/proc` and, in WSL, the Windows drives under `/mnt/` are left out. Each filesystem is searched once, even if it's mounted in several places, and the search never crosses into another filesystem, including from a `-p` folder. Only regular files are listed: symbolic links aren't, but the files they point to are.

### Fields and output formats

| Field | Meaning |
|---|---|
| `Name` | File name |
| `Directory` | Full path of the folder the file is in |
| `Size` | Size in bytes |
| `Modified` | Last modified time, in ISO 8601 local time with its time-zone offset (e.g. `2026-11-12T10:54:59+08:00`) |
| `Category` | `Executable`, `Library`, `Script`, `Installer` or `Other`; see [Categories](#categories) |

Files are sorted by directory, then name, and a file found twice (e.g. from overlapping `-Path` folders) is listed once.

| Format | Shape |
|---|---|
| `text` | Aligned `Name` / `Directory` / `Size` / `Modified` / `Category` table |
| `csv` | Header `"Name","Directory","Size","Modified","Category"`, all fields quoted |
| `json` | Array of `{"Name": ..., "Directory": ..., "Size": <number>, "Modified": ..., "Category": ...}` objects |
| `html` | Full page titled "Executable files", with the file count and a table |

With BusyBox, whose `stat` doesn't report time zones, `Modified` uses the machine's current time-zone offset, which can be an hour off for files dated on the other side of a daylight-saving change.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | No executable files found. For `.sh`, also returned when the script is sourced. |
| `2` | Invalid option, format, category or `-p` folder (`.sh` only. In `.ps1`, an invalid `-Format` or `-Category`, or a missing `-Path` folder, raises an error.) |
