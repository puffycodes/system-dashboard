# System Dashboard (Go, Windows and Linux)

The same dashboard as [`src/powershell/`](../powershell/), built as a single self-contained binary for Windows or Linux. The web UI is embedded in the binary, so you can copy one file to a machine and run it with nothing installed. Go is only needed on the machine that builds it. See [docs/design-approach.md](../../docs/design-approach.md) for background (including the [Linux options](../../docs/design-approach.md#linux)), and [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md) for the features.

## Build

Requires Go 1.20 or later. Any OS can build for any target. From this folder:

```sh
# Windows (64-bit)
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard.exe .

# Linux, x86-64 and ARM64. CGO_ENABLED=0 gives a fully static binary that runs on any distro, including Alpine
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard-linux-amd64 .
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o system-dashboard-linux-arm64 .
```

In PowerShell, set the variables first, e.g. `$env:CGO_ENABLED='0'; $env:GOOS='linux'; $env:GOARCH='amd64'; go build ...`, then `Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED` afterwards. On the target OS itself, a plain `go build -o <name> .` is enough.

`-ldflags "-s -w"` strips debug info, giving binaries of about 5 MB. Build output is git-ignored.

On Windows, `scripts\build.ps1` runs the builds above and writes the binaries to this folder, without running the tests. It builds `system-dashboard.exe` by default; pick targets with `-Target linux-amd64`, `-Target windows-amd64, linux-arm64` or `-Target all`, and set the path of a single binary with `-OutFile <path>`.

To build all three targets and package them for copying to other machines, use the packaging scripts instead: `scripts\package.ps1` on Windows or `scripts/package.sh` on Linux/macOS. They also run `go vet` and `go test` first. See [Packaging](../../README.md#packaging) in the root README. The scripts repeat the targets and build flags above, so if you change those, update `scripts/package.ps1`, `scripts/package.sh` and `scripts/build.ps1` too.

## Run

**Windows:** double-click `system-dashboard.exe`. It opens `http://localhost:8080/` in the default browser.

**Linux:** copy the package from the packaging scripts over, then extract and run it:

```sh
tar -xzf system-dashboard-<version>-linux-amd64.tar.gz
./system-dashboard-linux-amd64
```

If you copy the bare binary instead, run `chmod +x system-dashboard-linux-amd64` first; copying through Windows or a USB stick usually drops the executable permission.

It opens the browser with `xdg-open` if there's a graphical session. On a headless machine, view it from your own machine over SSH; the binary prints this hint on start:

```sh
ssh -L 8080:localhost:8080 user@host    # then open http://localhost:8080/ locally
```

Options (same on both):

```sh
-port 9000       # different port (default 8080)
-open=false      # don't try to open a browser
```

Press Ctrl+C to stop the server. On Linux, SIGTERM (`kill`, systemd) also stops it cleanly.

The server listens on `127.0.0.1` only, so other machines can't reach it except through SSH. The API has no authentication, so keep it that way.

## Test

```sh
go vet ./...
go test ./...
```

Tests run for the OS you're on:

- **Both OSes:** the routes (static files, content types, the API, error statuses), using a stub software list.
- **Windows:** the registry read and de-duplication.
- **Linux:** the parsers for each package manager's output, using sample output, plus a live read of whatever package manager is present.

To check vet on the other OS without running tests: `GOOS=linux go vet ./...`. To run the Linux tests from Windows, build a test binary and run it in WSL:

```sh
CGO_ENABLED=0 GOOS=linux go test -c -o linux.test .    # then in WSL: ./linux.test -test.v
```

## Layout

| Path | Purpose |
|---|---|
| `main.go` | Flags, listener, Ctrl+C/SIGTERM shutdown |
| `server.go` | HTTP routes (`/api/*` and the embedded static files), and the shared `Software` type |
| `software_windows.go` | `getInstalledSoftware` on Windows: the registry Uninstall keys |
| `software_linux.go` | `getInstalledSoftware` on Linux: dpkg / rpm / pacman / apk, plus Flatpak and Snap |
| `browser_windows.go`, `browser_linux.go` | Open the default browser (`rundll32` / `xdg-open`) |
| `www/` | The UI, embedded at build time. A copy of `src/powershell/www/` |
| `*_test.go` | Tests (`_windows` / `_linux` files run only on that OS) |

Go picks the `_windows.go` or `_linux.go` files automatically from the build target. The only dependency is `golang.org/x/sys`, used for registry access on Windows.

## API

Identical to the PowerShell version, so they share the same UI:

| Route | Returns |
|---|---|
| `GET /api/software` | `{ "computerName": "...", "generatedAt": "<RFC 3339>", "items": [{ "Name": "...", "Version": "..." }] }` |

Unknown `/api/` routes return `{ "error": "..." }` with a 404 status.

The software lists match the other implementations entry for entry:

- **Windows:** the same as [`list_installed_software.ps1`](../useful-scripts/list_installed_software.ps1) and the PowerShell dashboard: the same registry keys and filtering, de-duplicated case-insensitively.
- **Linux:** the same as [`list_installed_software.sh`](../useful-scripts/list_installed_software.sh): the same sources, de-duplicated and sorted byte-wise like `LC_ALL=C sort -u`. On Linux, names are package names (e.g. `libc6`), and the list includes libraries.

## Keeping in sync

- **UI:** `go:embed` can't reach files outside this folder, so `www/` is a copy of `src/powershell/www/`. When you change the UI, change both copies, or copy one over the other.
- **Software lists:** if you change what the `.ps1` or `.sh` script lists, change `software_windows.go` or `software_linux.go` to match.

## Adding a panel

1. Describe the feature in [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md), which both implementations follow.
2. Add a collector function for each OS (`<name>_windows.go` and `<name>_linux.go`). Put shared types in `server.go`.
3. Add a route for it in `newHandler` in `server.go`, and a test in `server_test.go`.
4. Add a `<section class="card">` to `www/index.html` and a loader in `www/app.js`, in both UI copies.
