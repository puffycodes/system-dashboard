# System Dashboard (PowerShell)

A local web dashboard that runs on a stock Windows 10/11 machine with nothing installed. Windows PowerShell 5.1 serves the API and the static page via `System.Net.HttpListener`, and the browser renders the UI. See [docs/design-approach.md](../../docs/design-approach.md) for why this approach was chosen, and [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md) for the features.

## Run

Double-click `start.cmd`, or from PowerShell:

```powershell
.\server.ps1 -Open                 # http://localhost:8080/
.\server.ps1 -Port 9000            # different port
.\server.ps1 -Help                 # show the options and exit
.\server.ps1 -Version              # print the version and exit
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Open   # if the execution policy blocks scripts
```

Press Ctrl+C in the console window to stop the server.

The server listens on `localhost` only, so other machines can't reach it. The API has no authentication, so keep it that way. Binding to `localhost` also means no admin rights or URL ACL are needed.

## Copying to another machine

Run `.\scripts\package.ps1 -SkipGo` from the repo root (or without `-SkipGo` to build the Go version too). It writes `dist\system-dashboard-<version>-powershell.zip`, which contains only the files below in a `system-dashboard\` folder. Extract it on the target machine and double-click `start.cmd`. See [Copying the dashboard to another machine](../../README.md#copying-the-dashboard-to-another-machine) in the root README.

## Layout

| Path | Purpose |
|---|---|
| `server.ps1` | HTTP server: routes `/api/*` to collectors, serves everything else from `www/` |
| `modules/SystemDashboard.psm1` | Data collectors (`Get-InstalledSoftware`) that return plain objects |
| `www/index.html`, `www/app.js`, `www/style.css` | The UI: plain HTML/JS/CSS, no build step or libraries |
| `start.cmd` | Double-click launcher (bypasses the execution policy, opens the browser) |

The packaging scripts copy `start.cmd`, `server.ps1`, and everything in `modules/` and `www/`. A new file in those folders is packaged automatically. They also write a `VERSION` file with the package version, which `server.ps1 -Version` prints; without it, as in a git checkout, `-Version` prints `git describe --tags --always --dirty`, or `dev` if git isn't available. If you add a file next to `server.ps1`, add it to `scripts/package.ps1` and `scripts/package.sh`.

## API

| Route | Returns |
|---|---|
| `GET /api/software` | `{ "computerName": "...", "generatedAt": "<ISO 8601>", "items": [{ "Name": "...", "Version": "..." }] }` |

Errors come back as `{ "error": "..." }` with a 404 or 500 status.

## Keeping in sync with the Go version

[`src/go/`](../go/) is the same dashboard as a self-contained binary for Windows and Linux. It serves the same API and keeps its own copy of the UI:

- **UI:** `src/go/www/` is a copy of `www/`. When you change the UI, change both copies, or copy one over the other.
- **Software list:** `Get-InstalledSoftware` and `src/go/software_windows.go` use the same registry keys and filtering as [`list_installed_software.ps1`](../useful-scripts/list_installed_software.ps1). If you change one, change the others to match.

## Adding a panel

1. Describe the feature in [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md), which both implementations follow.
2. Add a collector function to `modules/SystemDashboard.psm1` and include it in `Export-ModuleMember`.
3. Add a route for it in `Invoke-Request` in `server.ps1`.
4. Add a `<section class="card">` to `www/index.html` and a loader in `www/app.js`.
5. Add the same panel to the Go version (see [src/go/README.md](../go/README.md#adding-a-panel)), or note that it's PowerShell-only.
