# List Installed Software

Scripts that list the software installed on a machine, with each item's name and version.
Requirements: [docs/spec/list_installed_software.md](docs/spec/list_installed_software.md).

| Script | Platform | Output formats | Default output |
|---|---|---|---|
| [`list_installed_software.ps1`](#powershell-windows) | Windows (PowerShell 5.1+) | text, csv, json, html | stdout |
| [`list_installed_software.sh`](#sh-linux) | Linux (any POSIX `sh`) | text, csv, json, html | stdout |
| [`list_installed_software.bat`](#batch-windows) | Windows (cmd) | text only | `installed_software.txt` |

On Windows, use the PowerShell script. It implements the full spec and handles special characters in names correctly. The batch script is kept for machines where PowerShell isn't available.

## PowerShell (Windows)

```powershell
.\list_installed_software.ps1 [-Format text|csv|json|html] [-OutFile <path>]
```

| Parameter | Default | Description |
|---|---|---|
| `-Format` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-OutFile` | *(stdout)* | File to write to (UTF-8). If omitted, output is printed. |

Examples:

```powershell
.\list_installed_software.ps1
.\list_installed_software.ps1 -Format csv  -OutFile installed_software.csv
.\list_installed_software.ps1 -Format json -OutFile installed_software.json
.\list_installed_software.ps1 -Format html -OutFile installed_software.html
```

If the execution policy blocks the script, run it with:

```powershell
powershell -ExecutionPolicy Bypass -File .\list_installed_software.ps1 -Format csv
```

Help: `Get-Help .\list_installed_software.ps1 -Full`

## sh (Linux)

```sh
sh list_installed_software.sh [-f text|csv|json|html] [-o output_file]
```

| Option | Default | Description |
|---|---|---|
| `-f` | `text` | Output format: `text`, `csv`, `json` or `html`. |
| `-o` | *(stdout)* | File to write to. If omitted, output is printed. |
| `-h` | | Show usage. |

Examples:

```sh
sh list_installed_software.sh
sh list_installed_software.sh -f csv  -o installed_software.csv
sh list_installed_software.sh -f json -o installed_software.json
./list_installed_software.sh -f html -o installed_software.html   # after chmod +x
```

> **Run it, don't source it.** `source list_installed_software.sh` or `. ./list_installed_software.sh` is refused, because the script's `set -eu` would otherwise stay on in your shell and break things like prompt hooks (e.g. `bash: Q_LOG_LEVEL: unbound variable`).

## Batch (Windows)

```bat
list_installed_software.bat [output_file]
```

It writes a `Name  |  Version` list, with a header line giving the computer name and date, to `output_file`. If you don't give a file, it writes `installed_software.txt` next to the script. It also prints the list to the console.

Limitations: text output only. Names containing `%`, `^` or `"` may be mangled.

## What is listed

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

## Output formats

| Format | Shape |
|---|---|
| `text` | Aligned `Name` / `Version` table |
| `csv` | Header `"Name","Version"`, all fields quoted |
| `json` | Array of `{"Name": ..., "Version": ...}` objects |
| `html` | Full page with a title (computer name), timestamp, item count and a `Name` / `Version` table |

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | No installed software found. For `.sh`, also returned when the script is sourced. |
| `2` | Invalid option or format (`.sh` only. In `.ps1`, an invalid `-Format` raises a parameter validation error.) |
