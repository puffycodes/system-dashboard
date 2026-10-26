# System Dashboard (Go, Windows)

The same dashboard as [`src/powershell/`](../powershell/), built as a single self-contained `system-dashboard.exe`. The web UI is embedded in the binary, so you can copy the `.exe` to any 64-bit Windows machine and run it with nothing installed. Go is only needed on the machine that builds it. See [docs/design-approach.md](../../docs/design-approach.md) for background, and [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md) for the features.

## Build

Requires Go 1.20 or later. From this folder:

```sh
go build -trimpath -ldflags "-s -w" -o system-dashboard.exe .
```

`-ldflags "-s -w"` strips debug info, giving a binary of about 5 MB. To build from Linux or macOS, set the target first: `GOOS=windows GOARCH=amd64 go build ...`.

Build output (`*.exe`) is git-ignored.

## Run

Double-click `system-dashboard.exe`. It opens `http://localhost:8080/` in the default browser. Or from a terminal:

```powershell
.\system-dashboard.exe                   # http://localhost:8080/, opens the browser
.\system-dashboard.exe -port 9000        # different port
.\system-dashboard.exe -open=false       # don't open the browser
```

Press Ctrl+C in the console window, or close it, to stop the server.

The server listens on `127.0.0.1` only, so other machines can't reach it. The API has no authentication, so keep it that way.

## Test

```sh
go vet ./...
go test ./...
```

The tests cover the routes (static files, content types, the API, and error statuses) using a stub software list. They also read the real registry, so they must run on Windows.

## Layout

| Path | Purpose |
|---|---|
| `main.go` | Flags, listener, browser launch, Ctrl+C shutdown |
| `server.go` | HTTP routes: `/api/*` and the embedded static files |
| `software_windows.go` | `getInstalledSoftware`: reads the registry Uninstall keys |
| `www/` | The UI, embedded at build time. A copy of `src/powershell/www/` |
| `*_test.go` | Tests |

The only dependency is `golang.org/x/sys` for registry access.

## API

Identical to the PowerShell version, so the two can share the same UI:

| Route | Returns |
|---|---|
| `GET /api/software` | `{ "computerName": "...", "generatedAt": "<RFC 3339>", "items": [{ "Name": "...", "Version": "..." }] }` |

Unknown `/api/` routes return `{ "error": "..." }` with a 404 status.

The software list uses the same registry keys and filtering as the PowerShell version, so both return the same entries.

## Keeping in sync with the PowerShell version

`go:embed` can't reach files outside this folder, so `www/` is a copy of `src/powershell/www/`. When you change the UI, change both copies, or copy one over the other.

## Adding a panel

1. Add a collector function in its own file (`<name>_windows.go` for Windows-only code).
2. Add a route for it in `newHandler` in `server.go`, and a test in `server_test.go`.
3. Add a `<section class="card">` to `www/index.html` and a loader in `www/app.js`, in both UI copies.
