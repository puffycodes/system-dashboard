# Design Approach: Running Scripts Without Installing Software

Goal: run scripts/programs on a Windows machine without installing extra runtimes such as Python or Node.js.

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

- **Go**: `go build` produces one static `.exe`. Simplest option for small tools. The dashboard is also built this way in [`src/windows-go/`](../src/windows-go/).
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
