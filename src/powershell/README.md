# System Dashboard (PowerShell)

A local web dashboard that runs on a stock Windows 10/11 machine with nothing installed. Windows PowerShell 5.1 serves the API and the static page via `System.Net.HttpListener`, and the browser renders the UI. See [docs/design-approach.md](../../docs/design-approach.md) for why this approach was chosen, and [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md) for the features.

## Run

Double-click `start.cmd`, or from PowerShell:

```powershell
.\server.ps1 -Open                 # http://localhost:8080/
.\server.ps1 -Port 9000            # different port
powershell -ExecutionPolicy Bypass -File .\server.ps1 -Open   # if the execution policy blocks scripts
```

Press Ctrl+C in the console window to stop the server.

The server listens on `localhost` only, so other machines can't reach it. The API has no authentication, so keep it that way. Binding to `localhost` also means no admin rights or URL ACL are needed.

## Layout

| Path | Purpose |
|---|---|
| `server.ps1` | HTTP server: routes `/api/*` to collectors, serves everything else from `www/` |
| `modules/SystemDashboard.psm1` | Data collectors (`Get-InstalledSoftware`) that return plain objects |
| `www/index.html`, `www/app.js`, `www/style.css` | The UI: plain HTML/JS/CSS, no build step or libraries |
| `start.cmd` | Double-click launcher (bypasses the execution policy, opens the browser) |

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

1. Add a collector function to `modules/SystemDashboard.psm1` and include it in `Export-ModuleMember`.
2. Add a route for it in `Invoke-Request` in `server.ps1`.
3. Add a `<section class="card">` to `www/index.html` and a loader in `www/app.js`.
4. Add the same panel to the Go version (see [src/go/README.md](../go/README.md#adding-a-panel)), or note that it's PowerShell-only.
