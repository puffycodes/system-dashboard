# System Dashboard

Tools for inspecting a machine without installing any extra software (no Python, Node.js, etc.) on it. The scripts and the PowerShell dashboard run on what the operating system already ships with. The Go dashboard is built once on any machine with Go, and then runs as a single self-contained binary.

## What's here

| Path | What it is |
|---|---|
| [`src/powershell/`](src/powershell/) | The system dashboard: a local web page served by Windows PowerShell 5.1. Shows the host name and IP addresses, with a tab for the installed software and a tab for the executable files on the local disks, searched on request by category. Each list is a filterable, sortable table that can be downloaded as text, csv, json or html. |
| [`src/go/`](src/go/) | The same dashboard as a single self-contained binary for Windows or Linux, written in Go. Build it once, then copy it to any machine. |
| [`src/useful-scripts/`](src/useful-scripts/) | Standalone scripts for PowerShell and POSIX `sh` (Linux). `list_host_information` (also for cmd) lists the host name, IP addresses and timestamp. `list_installed_software` (also for cmd) lists the installed software. `list_executables` lists the executable files on the local disks with their directory, size, last modified time and category (executable, dynamic library, script, installer or other). Both lists are tagged with the host name and timestamp (which an option turns off). Output as text, csv, json or html. |
| [`scripts/`](scripts/) | `build.ps1` (Windows) and `build.sh` (Linux/macOS): build the bare Go binaries into `src/go/`. `package.ps1` and `package.sh`: build the dashboard and package the files each target machine needs into `dist/`. |
| [`docs/design-approach.md`](docs/design-approach.md) | Options for running programs without installing software on Windows and Linux, and why the dashboard uses PowerShell and Go. |
| [`docs/spec/`](docs/spec/) | Requirements for the [dashboard](docs/spec/system-dashboard.md), the [host information](docs/spec/list_host_information.md), the [installed-software list](docs/spec/list_installed_software.md), the [executables list](docs/spec/list_executables.md), and [macOS support](docs/spec/macos.md). |

## Quick start

**Dashboard (Windows):** double-click `src/powershell/start.cmd`, or run:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\powershell\server.ps1 -Open
```

It opens at `http://localhost:8080/` and is only reachable from this machine. Press Ctrl+C in the console window to stop it. See [src/powershell/README.md](src/powershell/README.md).

**Dashboard as a single binary (Go, Windows or Linux):** build it on any machine with Go 1.20+, then copy the binary to the target:

```sh
cd src/go
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard.exe .
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard-linux-amd64 .
```

Or run the build script from the repo root, which writes the binaries to `src/go/`: `.\scripts\build.ps1 -Target all` on Windows, `./scripts/build.sh -t all` on Linux/macOS.

On Windows, double-click `system-dashboard.exe`. On Linux, run `./system-dashboard-linux-amd64`; on a headless server, view it with `ssh -L 8080:localhost:8080 user@host`. See [src/go/README.md](src/go/README.md).

**Host information:**

```powershell
# Windows
.\src\useful-scripts\list_host_information.ps1 -Format json -OutFile host_information.json
```

```sh
# Linux
sh src/useful-scripts/list_host_information.sh -f json -o host_information.json
```

**Installed-software list:**

```powershell
# Windows
.\src\useful-scripts\list_installed_software.ps1 -Format csv -OutFile installed_software.csv
```

```sh
# Linux
sh src/useful-scripts/list_installed_software.sh -f csv -o installed_software.csv
```

**Executables list:**

```powershell
# Windows (as administrator, to search every folder)
.\src\useful-scripts\list_executables.ps1 -Format csv -OutFile executables.csv
```

```sh
# Linux
sudo sh src/useful-scripts/list_executables.sh -f csv -o executables.csv
```

See [src/useful-scripts/README.md](src/useful-scripts/README.md) for all options.

## Copying the dashboard to another machine

Only the files below are needed on the target machine: no source code or Go installation.

### Packaging

The packaging scripts build everything and put exactly these files in one archive per target, in `dist/`:

```powershell
.\scripts\package.ps1             # Windows: uses the built-in tar.exe (Windows 10 1803+)
.\scripts\package.ps1 -SkipGo     # only the PowerShell version, if Go isn't installed
```

```sh
./scripts/package.sh              # Linux/macOS: needs zip, bsdtar or python3 for the .zip files
./scripts/package.sh -n           # only the PowerShell version, if Go isn't installed
```

| Archive in `dist/` | Contents | For |
|---|---|---|
| `system-dashboard-<version>-powershell.zip` | The PowerShell version's files (layout below) | Windows, PowerShell version |
| `system-dashboard-<version>-windows-amd64.zip` | `system-dashboard.exe`, `README.txt` | Windows, Go version |
| `system-dashboard-<version>-linux-amd64.tar.gz` | `system-dashboard-linux-amd64`, `README.txt` | Linux x86-64 |
| `system-dashboard-<version>-linux-arm64.tar.gz` | `system-dashboard-linux-arm64`, `README.txt` | Linux ARM64 |
| `SHA256SUMS` | Checksums of the archives | Check a copy with `sha256sum -c SHA256SUMS` |

Each archive's files are in a folder named after the archive, e.g. `system-dashboard-<version>-windows-amd64/`, so extracting one never mixes them with other files, even another of these packages.

Each archive includes a short `README.txt` on starting, stopping and the options for that package. They are made from the templates in [`scripts/package-readme/`](scripts/package-readme/), with the version filled in. They repeat the dashboards' options, so if you change an option, update them too.

`<version>` defaults to `git describe --tags --always --dirty`: the latest tag or commit, plus `-dirty` if tracked files have uncommitted changes. The Go binaries print the same version with `-version`, and the PowerShell version with `-Version`. Set it with `-Version` / `-v`, and the output folder with `-OutDir` / `-o`. Before building, the scripts run `go vet` and `go test` and stop if either fails. They take files from the working tree, so uncommitted changes are included. `dist/` is git-ignored.

The `.tar.gz` archives keep the Linux binaries executable, even when packaged on Windows: `tar -xzf system-dashboard-<version>-linux-amd64.tar.gz`, then `cd system-dashboard-<version>-linux-amd64` and run `./system-dashboard-linux-amd64`. Zip archives also avoid email filters that block `.exe` attachments.

### Go version (simplest)

| Target | Copy this one file |
|---|---|
| Windows | `system-dashboard.exe` |
| Linux x86-64 | `system-dashboard-linux-amd64` |
| Linux ARM64 | `system-dashboard-linux-arm64` |

The web page is embedded in the binary, so that's all you need. On Linux, `uname -m` tells you which one: `x86_64` means amd64, `aarch64` means arm64.

The binaries are build output, not files in git. Build them with `scripts\build.ps1` / `scripts/build.sh` or the commands in [src/go/README.md](src/go/README.md#build), or take them from the packages above.

- **Linux:** copying the bare binary through Windows or a USB stick usually drops the executable permission. Run `chmod +x system-dashboard-linux-amd64` before starting it. `scp -p` and the `.tar.gz` packages keep the permission.
- **Windows:** the `.exe` isn't code-signed. If it arrives by download or email, SmartScreen may warn on first run; choose **More info**, then **Run anyway**.

### PowerShell version (Windows)

Copy the whole folder and keep its layout, because `server.ps1` looks for `modules\` and `www\` next to itself:

```
system-dashboard-<version>-powershell\
├── start.cmd                      (double-click launcher; optional but convenient)
├── server.ps1
├── VERSION                        (written by the packaging scripts; read by server.ps1 -Version)
├── README.txt                     (written by the packaging scripts: how to run it)
├── modules\
│   └── SystemDashboard.psm1
└── www\
    ├── index.html
    ├── app.js
    └── style.css
```

That's the contents of [`src/powershell/`](src/powershell/) without `README.md`, plus the `VERSION` and `README.txt` files. Double-click `start.cmd` to run it.

If the files arrive by download, Windows marks them as coming from the internet. `start.cmd` bypasses the script policy, so it still works. If you run `server.ps1` directly instead, unblock the files first: `Get-ChildItem -Recurse | Unblock-File`.

## Line endings

[`.gitattributes`](.gitattributes) checks out all text files with LF, except `.bat` and `.cmd` files, which use CRLF because cmd.exe can mis-parse batch files with LF endings. If you add a file type that needs CRLF, add a rule for it there.
