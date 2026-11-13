# To Do

## macOS support

The spec ([docs/spec/macos.md](spec/macos.md)), the `.sh` scripts, the Go dashboard and the packaging are done. So far they have only been tested off a Mac: the scripts in a fake macOS environment in WSL, the macOS parsing with unit tests on Windows and Linux, and the packages by checking their contents. What's left needs a real Mac.

### Before a release: run on a real Mac

Apple silicon at least, and Intel if one is available. macOS 12 (Monterey) or later.

- [*] **Compare the lists.** Run the scripts and the dashboard and check that they list the same entries, as on the other platforms:
    - Host information: `list_host_information.sh` and the dashboard's host name and IP addresses.
    - Installed software: `list_installed_software.sh` and the Software tab.
    - Executables: `list_executables.sh -c all` and the Executables tab with all categories.
- [*] **Run the Go tests on the Mac:** `go test ./...` in `src/go`. The `_darwin` tests (the live software list, the executables' categories on sample files, and the local volumes) have only been compiled, not run.
- [*] **Check the scripts with the `/bin/sh` and BSD tools that macOS ships**, not just the fake macOS environment: `mount`, `ifconfig`, BSD `stat`, `plutil` and `/usr/share/firmlinks`.
- [*] **Run `list_executables.sh` as an ordinary user.** The fake environment ran as root, so a file that can't be read, which should count as Executable, was never tested.
- [*] **Check what is left out:** the apps that come with macOS (e.g. Safari), macOS's support volumes, Time Machine snapshots, and network shares (except with `-a`).
- [ ] **Check Full Disk Access.** Compare the executables list with Full Disk Access off and on for Terminal, and check that the README's steps are right.

### Packages

- [ ] **Download a package and run it.** Download or AirDrop each `.tar.gz` so that macOS marks it, extract it, and check:
    - The binary is still executable.
    - macOS blocks it, and each way in `README.txt` allows it: `xattr -d com.apple.quarantine`, Control-click > Open, and on macOS 15 and later, Open Anyway in System Settings.
    - It opens the dashboard in the default browser, `-version` prints the package's version, and Ctrl+C stops it.
- [ ] **Run the Intel binary on an Intel Mac.** It isn't signed, unlike the Apple silicon one, which Go's linker signs ad hoc. Intel Macs should allow that; check that they do.
- [*] **Run `scripts/package.sh` and `scripts/build.sh` on a Mac.** They have only been run from Git Bash on Windows, where `chmod` has no effect. On the Mac, check that:
    - The binaries in the archives are executable.
    - The archives have no `._` files.
    - `build.sh` with no `-t` builds the binary for the Mac's CPU.
