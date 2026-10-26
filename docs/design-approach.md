# Design Approach: Running Scripts Without Installing Software

Goal: run scripts/programs on a machine without installing extra runtimes such as Python or Node.js. Sections 1–3 cover Windows; [Linux](#linux) is covered at the end.

## 1. Use what Windows already ships (zero install)

| Option | Good for | Notes |
|---|---|---|
| **PowerShell 5.1** (`.ps1`) | Most scripting: files, registry, WMI/CIM system info, REST calls, small web servers, GUIs | Ships with every Windows 10/11. Has the full .NET Framework available. Run with `powershell -ExecutionPolicy Bypass -File script.ps1` to get past the default script policy. |
| **Batch / cmd** (`.bat`, `.cmd`) | Simple glue: running programs in order, setting env vars | Painful for anything with real logic. |
| **C# via the built-in compiler** | Real compiled `.exe` programs | .NET Framework 4.x includes `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`. `csc.exe app.cs` produces an `.exe` with no SDK installed (C# 5 syntax only, full Framework library). PowerShell can also compile inline C# with `Add-Type -TypeDefinition '...'`. |
| **HTML + JavaScript in the browser** | UIs, dashboards, calculators | Open a local `.html` file in Edge. No system access on its own; pair it with a PowerShell backend. |
| **JScript / VBScript (`cscript`)** | Legacy only | VBScript is deprecated and being removed from Windows 11. Do not use for new work. |

### Fit for this project (system dashboard)

A PowerShell script collects system data (`Get-CimInstance Win32_Processor`, `Get-Counter`, `Get-Process`, etc.) and serves it with `System.Net.HttpListener` on `http://localhost:8080`. A plain HTML/JS page displays it. The whole stack needs no installs.

This is the approach the dashboard uses; it's implemented in [`src/powershell/`](../src/powershell/).

## 2. Build elsewhere, ship one self-contained executable

If tools can be installed on the build machine but not the target, compile to a single `.exe` that carries its own runtime:

- **Go**: `go build` produces one static `.exe`. Simplest option for small tools. The dashboard is also built this way in [`src/go/`](../src/go/).
- **Rust**: same idea; very small, fast binaries.
- **.NET 8+**: `dotnet publish -r win-x64 --self-contained -p:PublishSingleFile=true`.
- **Python**: PyInstaller (`pyinstaller --onefile script.py`) or Nuitka.
- **JS/TS**: `deno compile`, `bun build --compile`, or Node single executable applications (SEA).

## 3. Portable runtimes (no installer, just unzip)

- **Python embeddable package**: a zip from python.org. Unzip and run `python.exe`; it doesn't touch the registry or PATH.
- **Node.js** and **Deno** also come as zip or single-`.exe` downloads that run from a folder or USB stick.

These are still "other software", just not installed.

## Recommendation

- Machine is locked down and must stay untouched: **PowerShell**, with inline C# when more power or speed is needed.
- Handing people a tool to double-click: write it in **Go** (or .NET single-file) and ship the `.exe`.

## Linux

The same goal on Linux: run the dashboard on a stock machine with nothing installed. Linux has no equivalent of PowerShell's built-in `HttpListener`, so the dashboard needs either a compiled binary or a static report.

### What a stock Linux machine gives you

| Option | Problem |
|---|---|
| **POSIX `sh` + coreutils/awk** | Always present, and it can collect the data ([`list_installed_software.sh`](../src/useful-scripts/list_installed_software.sh) does). But it can't run a web server: bash's `/dev/tcp` can only make outgoing connections, not listen. |
| **`nc`, `socat`, `busybox httpd`** | Could act as the web server, but none of them is guaranteed to be installed, and `nc` comes in several incompatible versions. |
| **Python 3** | Preinstalled on Ubuntu and Fedora, but not on minimal Debian, Alpine or most container images. |
| **Perl** | Present on most distros, but not Alpine or minimal images, and a poor fit for whoever maintains this later. |

### Option A: one Go codebase for Windows and Linux (chosen)

Go builds a fully static Linux binary with `CGO_ENABLED=0 GOOS=linux go build`. It doesn't depend on the system's C library, so the same file runs on Debian, RHEL, Arch, Alpine and so on.

Only data collection is OS-specific. Go picks the right file at build time by its `_windows.go` / `_linux.go` suffix:

- `software_windows.go` reads the registry, like the PowerShell version.
- `software_linux.go` lists packages the same way as `list_installed_software.sh`: the first of dpkg, rpm, pacman or apk, plus Flatpak and Snap. It produces exactly the same entries as the script.
- The server, API and UI are shared. Opening the browser uses `rundll32` on Windows and `xdg-open` on Linux. On Linux it's skipped when there's no graphical session.

One build step produces `system-dashboard.exe`, `system-dashboard-linux-amd64` and `system-dashboard-linux-arm64`. This avoids a third copy of the UI and server. Implemented in [`src/go/`](../src/go/), which was renamed from `src/windows-go/` when Linux support was added.

### Option B: a static report from a shell script (not chosen)

`sh dashboard.sh` would write the same page plus a `data.js` file containing the software list, to open with `xdg-open` or copy elsewhere. It needs nothing beyond `sh`. But it's a snapshot: the page can't reload the list itself, so Refresh means re-running the script. The data must be in `data.js` rather than `.json`, because browsers block `fetch()` of local files from a page opened from disk.

Only worth building if shipping a binary is not allowed at all.

### Headless servers

Most Linux machines you'd inspect have no browser. The dashboard still listens on `127.0.0.1` only, and you view it over SSH from your own machine:

```sh
ssh -L 8080:localhost:8080 user@host
```

Then open `http://localhost:8080/` locally. The binary prints this hint when it can't open a browser.
