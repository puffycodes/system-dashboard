# System Dashboard (Go, Windows, Linux and macOS)

The same dashboard as [`src/powershell/`](../powershell/), built as a single self-contained binary for Windows, Linux or macOS. The web UI is embedded in the binary, so you can copy one file to a machine and run it with nothing installed. Go is only needed on the machine that builds it. See [docs/design-approach.md](../../docs/design-approach.md) for background (including the [Linux options](../../docs/design-approach.md#linux)), [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md) for the features, and [docs/spec/macos.md](../../docs/spec/macos.md) for how it behaves on macOS.

## Build

Requires Go 1.20 or later. Any OS can build for any target. From this folder:

```sh
# Windows (64-bit)
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard.exe .

# Linux, x86-64 and ARM64. CGO_ENABLED=0 gives a fully static binary that runs on any distro, including Alpine
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard-linux-amd64 .
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o system-dashboard-linux-arm64 .

# macOS, Apple silicon and Intel
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o system-dashboard-darwin-arm64 .
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o system-dashboard-darwin-amd64 .
```

In PowerShell, set the variables first, e.g. `$env:CGO_ENABLED='0'; $env:GOOS='linux'; $env:GOARCH='amd64'; go build ...`, then `Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED` afterwards. On the target OS itself, a plain `go build -o <name> .` is enough.

`-ldflags "-s -w"` strips debug info, giving binaries of about 5 MB. Build output is git-ignored.

Go's linker signs the `darwin-arm64` binary ad hoc, which Apple silicon requires before a program can run, so it can be built on any OS without `codesign`. The `darwin-amd64` binary is unsigned, which Intel Macs allow.

The version that `-version` prints is set with `-ldflags "-s -w -X main.version=<version>"`. Without it, as in the commands above, the binary reports the commit it was built from, e.g. `f6ea795`, plus `-dirty` if there were uncommitted changes, or `dev` when built outside the git checkout.

On Windows, `scripts\build.ps1` runs the builds above and writes the binaries to this folder, without running the tests. It builds `system-dashboard.exe` by default; pick targets with `-Target linux-amd64`, `-Target windows-amd64, darwin-arm64` or `-Target all`, set the path of a single binary with `-OutFile <path>`, and set the version with `-Version <version>` (default: `git describe --tags --always --dirty`, as in the packaging scripts). `-Clean` removes the binaries from this folder.

On Linux/macOS, `scripts/build.sh` does the same. It builds the binary for the machine's OS (Linux or macOS) and CPU by default; pick targets with `-t linux-amd64`, `-t windows-amd64 -t darwin-arm64` or `-t all`, set the path of a single binary with `-o <path>`, set the version with `-v <version>`, and remove the binaries with `-c`.

To build all the targets and package them for copying to other machines, use the packaging scripts instead: `scripts\package.ps1` on Windows or `scripts/package.sh` on Linux/macOS. They also run `go vet` and `go test` first. See [Packaging](../../README.md#packaging) in the root README. The scripts repeat the targets and build flags above, so if you change those, update `scripts/package.ps1`, `scripts/package.sh`, `scripts/build.ps1` and `scripts/build.sh` too.

## Run

**Windows:** double-click `system-dashboard.exe`. It opens `http://localhost:8080/` in the default browser.

**Linux:** copy the package from the packaging scripts over, then extract and run it:

```sh
tar -xzf system-dashboard-<version>-linux-amd64.tar.gz
cd system-dashboard-<version>-linux-amd64
./system-dashboard-linux-amd64
```

If you copy the bare binary instead, run `chmod +x system-dashboard-linux-amd64` first; copying through Windows or a USB stick usually drops the executable permission.

It opens the browser with `xdg-open` if there's a graphical session. On a headless machine, view it from your own machine over SSH; the binary prints this hint on start:

```sh
ssh -L 8080:localhost:8080 user@host    # then open http://localhost:8080/ locally
```

**macOS:** run `./system-dashboard-darwin-arm64` (Apple silicon) or `./system-dashboard-darwin-amd64` (Intel) in Terminal. It opens the dashboard in the default browser with `open`. To list the executables in folders that macOS's privacy controls protect, give Terminal Full Disk Access first.

Options (same on every OS):

```sh
-port 9000       # different port (default 8080)
-open=false      # don't try to open a browser
-help            # show the options and exit (-h works too)
-version         # print the version and exit
```

Press Ctrl+C to stop the server. On Linux and macOS, SIGTERM (`kill`, systemd, launchd) also stops it cleanly.

The server listens on `127.0.0.1` only, so other machines can't reach it except through SSH. The API has no authentication, so keep it that way.

## Test

```sh
go vet ./...
go test ./...
```

Tests run for the OS you're on:

- **Every OS:** the routes (static files, content types, the API, error statuses, the `categories` parameter), using stub software and executables lists, and the executables' sorting. Also the macOS parsing in `macos.go`: the `mount` output, firmlinks, Mach-O signatures, framework binaries, app versions and Homebrew's folders and versions, so it can be tested without a Mac.
- **Windows:** the registry read and de-duplication; the extension categories, including `PATHEXT`; the fixed drives; and the `Sort-Object` comparison.
- **Linux:** the parsers for each package manager's output, using sample output, plus a live read of whatever package manager is present; the executables' categories on sample files; and the mount points.
- **macOS:** a live read of the apps and Homebrew; the executables' categories on sample files; and the local volumes.

To check vet on another OS without running tests: `GOOS=linux go vet ./...` or `GOOS=darwin go vet ./...`. To run the Linux tests from Windows, build a test binary and run it in WSL:

```sh
CGO_ENABLED=0 GOOS=linux go test -c -o linux.test .    # then in WSL: ./linux.test -test.v
```

## Layout

| Path | Purpose |
|---|---|
| `main.go` | Flags, listener, Ctrl+C/SIGTERM shutdown |
| `server.go` | HTTP routes (`/api/*` and the embedded static files), the shared `Software` type, and `ipAddresses` |
| `software_windows.go` | `getInstalledSoftware` on Windows: the registry Uninstall keys |
| `software_linux.go` | `getInstalledSoftware` on Linux: dpkg / rpm / pacman / apk, plus Flatpak and Snap |
| `software_darwin.go` | `getInstalledSoftware` on macOS: the `.app` bundles, plus Homebrew |
| `software_unix.go` | Shared by Linux and macOS: running commands, and turning `name<TAB>version` lines into the list |
| `executables.go` | The shared `Executable` type, the category names, and sorting |
| `executables_windows.go` | `findExecutables` on Windows: the fixed drives, by file extension |
| `executables_linux.go` | `findExecutables` on Linux: the local disks' filesystems, by execute bit, name and first bytes |
| `executables_darwin.go` | `findExecutables` on macOS: the local volumes, by execute bit, name and first bytes, with data-volume files under their usual paths |
| `executables_unix.go` | Shared by Linux and macOS: searching a filesystem without crossing into others, and reading a file's first bytes |
| `macos.go` | The macOS parsing, which builds on every OS so that its tests run anywhere |
| `browser_windows.go`, `browser_linux.go`, `browser_darwin.go` | Open the default browser (`rundll32` / `xdg-open` / `open`) |
| `www/` | The UI, embedded at build time. A copy of `src/powershell/www/` |
| `*_test.go` | Tests (`_windows` / `_linux` / `_darwin` / `_unix` files run only on that OS) |

Go picks the `_windows.go`, `_linux.go` or `_darwin.go` files automatically from the build target; the `_unix.go` files say `//go:build linux || darwin`. The only dependency is `golang.org/x/sys`, used for registry access on Windows.

## API

Identical to the PowerShell version, so they share the same UI:

| Route | Returns |
|---|---|
| `GET /api/host` | `{ "computerName": "...", "ipAddresses": ["..."], "generatedAt": "<RFC 3339>" }` |
| `GET /api/software` | `{ "computerName": "...", "generatedAt": "<RFC 3339>", "items": [{ "Name": "...", "Version": "..." }] }` |
| `GET /api/executables?categories=executable,library` | `{ "computerName": "...", "generatedAt": "<RFC 3339>", "categories": ["Executable", "Library"], "items": [{ "Name": "...", "Directory": "...", "Size": 123, "Modified": "...", "Category": "..." }] }` |

`categories` takes `list_executables`' `-c` names (`executable`, `library`, `script`, `installer`, `other` or `all`), case-sensitively; the default is `executable`. An unknown name or an empty list returns `{ "error": "..." }` with a 400 status, and unknown `/api/` routes return one with a 404 status. Only `GET` and `HEAD` are accepted; other methods return 405.

Requests are served concurrently, so the software list can be refreshed while the executables are being searched.

The software lists match the other implementations entry for entry:

- **Windows:** the same as [`list_installed_software.ps1`](../useful-scripts/list_installed_software.ps1) and the PowerShell dashboard: the same registry keys and filtering, de-duplicated case-insensitively.
- **Linux:** the same as [`list_installed_software.sh`](../useful-scripts/list_installed_software.sh): the same sources, de-duplicated and sorted byte-wise like `LC_ALL=C sort -u`. On Linux, names are package names (e.g. `libc6`), and the list includes libraries.
- **macOS:** the same as [`list_installed_software.sh`](../useful-scripts/list_installed_software.sh) on macOS: the same apps and Homebrew folders, de-duplicated and sorted byte-wise.

The executables lists match `list_executables` file for file, in the same order:

- **Windows:** the same as [`list_executables.ps1`](../useful-scripts/list_executables.ps1) and the PowerShell dashboard: the fixed drives, categories by extension, and the order of `Sort-Object`, which `compareLikeSortObject` reproduces with the Windows `CompareStringEx` function.
- **Linux:** the same as [`list_executables.sh`](../useful-scripts/list_executables.sh): the same filesystems from `/proc/self/mountinfo`, the same categories, and byte-wise order.
- **macOS:** the same as [`list_executables.sh`](../useful-scripts/list_executables.sh) on macOS: the same volumes from `mount`, the same usual paths from `/usr/share/firmlinks`, the same categories, and byte-wise order.

## Keeping in sync

- **UI:** `go:embed` can't reach files outside this folder, so `www/` is a copy of `src/powershell/www/`. When you change the UI, change both copies, or copy one over the other.
- **Software lists:** if you change what the `.ps1` or `.sh` script lists, change `software_windows.go`, `software_linux.go` or `software_darwin.go` (and `macos.go`) to match.
- **Executables lists:** if you change what `list_executables.ps1` or `.sh` lists, or its categories, change `executables_windows.go`, `executables_linux.go` or `executables_darwin.go` (and `macos.go`), and `Get-Executable` in the PowerShell version, to match.
- **Download formats:** `softwareFormats` and `executableFormats` in `www/app.js` write the same files as [`list_installed_software.sh`](../useful-scripts/list_installed_software.sh) and [`list_executables.sh`](../useful-scripts/list_executables.sh). If you change a script's output format, change it there too.
- **IP addresses:** `ipAddresses` in `server.go` skips the same addresses as the `list_host_information` `.ps1` and `.sh` scripts and `Get-IPAddress` in the PowerShell version: loopback and link-local. Like the scripts, it counts only interfaces that are up on Windows and macOS, and every interface on Linux. If you change one, change the others to match.

## Adding a tab

1. Describe the feature in [docs/spec/system-dashboard.md](../../docs/spec/system-dashboard.md), which both implementations follow.
2. Add a collector function for each OS (`<name>_windows.go`, `<name>_linux.go` and `<name>_darwin.go`). Put shared types in `server.go` or a shared `<name>.go`.
3. Add a route for it in `newHandler` in `server.go`, and a test in `server_test.go`.
4. In `www/index.html`, add a `role="tab"` button to the tab list and a `<section class="card" role="tabpanel">` for it; in `www/app.js`, add its loader. Do this in both UI copies.
