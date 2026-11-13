# macOS Support

How the scripts and the dashboard behave on macOS. Everything not covered here is the same as on Linux, as described in [list_host_information](list_host_information.md), [list_installed_software](list_installed_software.md), [list_executables](list_executables.md) and the [dashboard](system-dashboard.md).

## Platforms

- macOS 12 (Monterey) or later.
- Apple silicon (M1 and later, `arm64`) and Intel (`x86-64`).
- Runs on what macOS ships with: no Homebrew, Xcode or Command Line Tools needed.

## Scripts

- The existing `.sh` scripts also run on macOS. Each script detects macOS (`uname -s` is `Darwin`) and uses macOS sources and BSD tools there. There are no separate macOS scripts.
    - Same options, output formats and exit codes as on Linux.
    - Works with the `/bin/sh` that macOS ships.
- The dashboard reproduces the scripts' lists entry for entry, as on Windows and Linux.

## Host information

- Host Name: `uname -n`, as on Linux (e.g. `Janes-MacBook-Air.local`).
    - This is the name that `list_installed_software` and `list_executables` use, so files can still be matched by host.
- IP Addresses: the addresses of the network interfaces that are up, from `ifconfig`, IPv4 first.
    - Loopback and link-local addresses (`127.x.x.x`, `::1`, `169.254.x.x`, `fe80::`) are skipped, as on the other platforms.
    - Duplicate addresses are listed once.

## Installed software

- Lists:
    - Applications: the `.app` bundles in `/Applications` and `~/Applications`, and in their subfolders (e.g. `/Applications/Utilities`), but not `.app` bundles inside other bundles.
    - Homebrew formulae and casks, when Homebrew is installed: the same as `brew list --versions` and `brew list --cask --versions`.
        - Read from Homebrew's `Cellar` and `Caskroom` folders in `/opt/homebrew` (Apple silicon) and `/usr/local` (Intel), as `brew` is slow to start and refuses to run as root.
- Not listed:
    - The apps that come with macOS (e.g. Safari, Mail), just as Windows' list leaves out system components. They are on the read-only system volume, whether they appear in `/Applications` or `/System/Applications`.
    - Installer receipts (`pkgutil --pkgs`): mostly Apple's own components and the parts of apps that are already listed.
- For an application:
    - Name: the bundle's name without `.app`, as Finder shows it (e.g. `Google Chrome`).
    - Version: the bundle's `CFBundleShortVersionString`, or `CFBundleVersion` if that is missing, or `N/A`.
- For a Homebrew formula or cask:
    - Name: the formula or cask name (e.g. `git`, `visual-studio-code`), as on Linux, where the name is the package name.
    - Version: the version Homebrew reports. If more than one version is installed, the latest.
- Duplicate name + version entries are listed once, as on the other platforms. An app installed as a cask can appear twice, once by its app name and once by its cask name, as their names differ.

## Executables

### What is searched

- Default: the local volumes.
    - Local volumes are the mounted filesystems that macOS marks as local, so network shares are left out. External disks and mounted disk images under `/Volumes` are included, as USB disks are on Linux.
    - macOS's own support volumes are left out: `/System/Volumes/VM`, `Preboot`, `Recovery`, `Update`, `xarts`, `iSCPreboot` and `Hardware`.
    - The system volume (`/`) and the data volume (`/System/Volumes/Data`) are searched. Files on the data volume are shown under their usual paths (e.g. `/Users/…`, `/Applications/…`), not under `/System/Volumes/Data`. Each file is listed once.
- The option to include all mounted filesystems (`-a`) also searches network shares.
- A folder given with `-p` is searched as on Linux, without crossing into another volume.
- Folders that can't be read are skipped, as on Linux. Some folders are protected by macOS privacy controls, even from root. The README explains how to grant Full Disk Access to the terminal so that they can be read.

### Categories

Each file is in one category, as on Linux:

| Category | macOS |
|---|---|
| Executable | A Mach-O program: a regular file with an execute bit that starts with a Mach-O or universal binary signature, or that can't be read |
| Library | A dynamic library: a file named `*.dylib` or `*.so`, with or without an execute bit, or a framework's binary with an execute bit (e.g. `Foo.framework/Versions/A/Foo`) |
| Script | A file with an execute bit that starts with `#!` |
| Installer | A file named `*.pkg`, `*.mpkg` or `*.dmg`, with or without an execute bit |
| Other | Any other file with an execute bit |

- Only regular files are listed, as on Linux. An installer package or `.app` bundle that is a folder is not itself listed, but the files inside it are (e.g. an app's program in `Contents/MacOS`).
- Java class files share the universal binary's signature. They are not programs, so with an execute bit they count as Other.

### Fields

- The same fields and order as on Linux.
- Modified: from BSD `stat`, in ISO 8601 local time with the file's own time-zone offset.

## Dashboard

- The Go version is built for `darwin-arm64` and `darwin-amd64`. The PowerShell version is not supported on macOS.
- Opening the browser on start uses the default browser (`open`).
- The Executables tab searches the local volumes, as list_executables does by default.

## Packaging

- Two more packages: `system-dashboard-<version>-darwin-arm64.tar.gz` and `system-dashboard-<version>-darwin-amd64.tar.gz`, each with the binary and a `README.txt`.
    - `.tar.gz`, so that the binary keeps its executable permission.
- The binary is signed ad hoc, which Apple silicon requires before a program can run. It is not signed with a Developer ID or notarized.
    - So macOS blocks a copy that was downloaded or emailed. The package's `README.txt` explains how to allow it: open it once with Control-click > Open, or remove the quarantine flag with `xattr -d com.apple.quarantine <binary>`.
- The build and package scripts accept the targets `darwin-arm64` and `darwin-amd64`, and `all` includes them.

## Testing

- The unit tests for the macOS parsing code (Homebrew output, `Info.plist` versions, Mach-O signatures, framework paths, the mount list) run on any machine.
- Before a release, the scripts and the dashboard are run on a real Mac, Apple silicon at least, and their lists compared, as on the other platforms.
