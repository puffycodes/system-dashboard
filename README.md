# System Dashboard

Tools for inspecting a machine without installing any extra software (no Python, Node.js, etc.) on it. The scripts and the PowerShell dashboard run on what the operating system already ships with. The Go dashboard is built once on any machine with Go, and then runs as a single self-contained binary.

## What's here

| Path | What it is |
|---|---|
| [`src/powershell/`](src/powershell/) | The system dashboard: a local web page served by Windows PowerShell 5.1. Currently shows the installed software in a filterable, sortable table. |
| [`src/go/`](src/go/) | The same dashboard as a single self-contained binary for Windows or Linux, written in Go. Build it once, then copy it to any machine. |
| [`src/useful-scripts/`](src/useful-scripts/) | Standalone `list_installed_software` scripts for PowerShell, POSIX `sh` (Linux) and cmd. Output as text, csv, json or html. |
| [`docs/design-approach.md`](docs/design-approach.md) | Options for running programs without installing software on Windows and Linux, and why the dashboard uses PowerShell and Go. |
| [`docs/spec/`](docs/spec/) | Requirements for the [dashboard](docs/spec/system-dashboard.md) and the [installed-software list](docs/spec/list_installed_software.md). |

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

On Windows, double-click `system-dashboard.exe`. On Linux, run `./system-dashboard-linux-amd64`; on a headless server, view it with `ssh -L 8080:localhost:8080 user@host`. See [src/go/README.md](src/go/README.md).

**Installed-software list:**

```powershell
# Windows
.\src\useful-scripts\list_installed_software.ps1 -Format csv -OutFile installed_software.csv
```

```sh
# Linux
sh src/useful-scripts/list_installed_software.sh -f csv -o installed_software.csv
```

See [src/useful-scripts/README.md](src/useful-scripts/README.md) for all options.

## Copying the dashboard to another machine

Only the files below are needed on the target machine: no READMEs, source code or Go installation.

### Go version (simplest)

| Target | Copy this one file |
|---|---|
| Windows | `system-dashboard.exe` |
| Linux x86-64 | `system-dashboard-linux-amd64` |
| Linux ARM64 | `system-dashboard-linux-arm64` |

The web page is embedded in the binary, so that's all you need. On Linux, `uname -m` tells you which one: `x86_64` means amd64, `aarch64` means arm64.

The binaries are build output, not files in git. Build them with the commands in [src/go/README.md](src/go/README.md#build).

- **Linux:** copying through Windows or a USB stick usually drops the executable permission. Run `chmod +x system-dashboard-linux-amd64` before starting it. `scp -p` keeps the permission.
- **Windows:** the `.exe` isn't code-signed. If it arrives by download or email, SmartScreen may warn on first run; choose **More info**, then **Run anyway**.

### PowerShell version (Windows)

Copy the whole folder and keep its layout, because `server.ps1` looks for `modules\` and `www\` next to itself:

```
system-dashboard\
├── start.cmd                      (double-click launcher; optional but convenient)
├── server.ps1
├── modules\
│   └── SystemDashboard.psm1
└── www\
    ├── index.html
    ├── app.js
    └── style.css
```

That's the contents of [`src/powershell/`](src/powershell/) without `README.md`. Double-click `start.cmd` to run it.

If the files arrive by download, Windows marks them as coming from the internet. `start.cmd` bypasses the script policy, so it still works. If you run `server.ps1` directly instead, unblock the files first: `Get-ChildItem -Recurse | Unblock-File`.

## Line endings

[`.gitattributes`](.gitattributes) checks out all text files with LF, except `.bat` and `.cmd` files, which use CRLF because cmd.exe can mis-parse batch files with LF endings. If you add a file type that needs CRLF, add a rule for it there.
