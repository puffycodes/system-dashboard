#!/bin/sh
# ---------------------------------------------------------------
#  package.sh
#  Packages the system dashboard for copying to target machines.
#
#  Writes one archive per target to the output folder, containing
#  only the files the target needs (see "Copying the dashboard to
#  another machine" in README.md):
#
#    system-dashboard-<version>-powershell.zip      PowerShell version: start.cmd, server.ps1, modules/, www/
#    system-dashboard-<version>-windows-amd64.zip   system-dashboard.exe
#    system-dashboard-<version>-linux-amd64.tar.gz  system-dashboard-linux-amd64, executable
#    system-dashboard-<version>-linux-arm64.tar.gz  system-dashboard-linux-arm64, executable
#    SHA256SUMS                                     checksums, for sha256sum -c
#
#  Each archive's files are in a folder named after the archive
#  (e.g. system-dashboard-<version>-linux-amd64), so extracting it
#  never mixes them with other files, even another of these packages.
#
#  Each archive also has a README.txt on running that package, made
#  from scripts/package-readme/<powershell|windows|linux>.txt with
#  the version (and the Linux binary's name) filled in. The Windows
#  ones get CRLF endings.
#
#  The Go binaries are built after running the Go tests. Zip files
#  need one of zip, bsdtar or python3. Earlier output of this script
#  in the output folder is replaced; other files are left alone.
#
#  Files are taken from the working tree, so uncommitted changes are
#  included. If tracked files have uncommitted changes, the default
#  version ends in "-dirty".
#
#  Usage:  package.sh [-v version] [-o output_dir] [-n]
#    -v  Version in the archive names, and reported by the Go
#        binaries with -version and the PowerShell version with
#        -Version (from a VERSION file added to its folder).
#        Default: git describe
#        --tags --always --dirty, or "dev" outside a git checkout.
#    -o  Output folder. Default: dist/ at the repo root.
#    -n  Only package the PowerShell version, so Go isn't needed.
# ---------------------------------------------------------------

# Refuse to be sourced: set -eu, trap and exit would leak into the caller's shell
if { [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$0}" != "$0" ]; } ||
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) true ;; *) false ;; esac; then
    echo "Run this script instead of sourcing it: sh package.sh [options]" >&2
    return 1
fi

set -eu

usage() {
    echo "Usage: $(basename "$0") [-v version] [-o output_dir] [-n]" >&2
    exit 2
}

REPO=$(cd "$(dirname "$0")/.." && pwd)
VERSION=
OUT=
SKIP_GO=
while getopts "v:o:nh" opt; do
    case "$opt" in
        v) VERSION=$OPTARG ;;
        o) OUT=$OPTARG ;;
        n) SKIP_GO=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

has() { command -v "$1" >/dev/null 2>&1; }
die() { echo "$*" >&2; exit 1; }

if [ -z "$SKIP_GO" ] && ! has go; then
    die "Go not found. Install Go 1.20+ to build the binaries, or use -n to package only the PowerShell version."
fi
if ! has zip && ! has bsdtar && ! has python3; then
    die "Making zip files needs one of: zip, bsdtar, python3."
fi

if [ -z "$VERSION" ]; then
    VERSION=$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null) || VERSION=dev
fi
VERSION=$(printf '%s' "$VERSION" | tr -c 'A-Za-z0-9._+-' '-')   # keep it safe in file names

OUT=${OUT:-$REPO/dist}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# Remove earlier output of this script only
rm -f "$OUT"/system-dashboard-*.zip "$OUT"/system-dashboard-*.tar.gz "$OUT/SHA256SUMS"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
trap 'exit 130' INT TERM

ARCHIVES=

# make_zip <zip path> <dir> <entry>...: zips the entries inside <dir>, stored by their names
make_zip() {
    zip_path=$1 zip_dir=$2
    shift 2
    if has zip; then
        (cd "$zip_dir" && zip -qr "$zip_path" "$@")
    elif has bsdtar; then
        bsdtar -a -cf "$zip_path" -C "$zip_dir" "$@"
    else
        (cd "$zip_dir" && python3 -m zipfile -c "$zip_path" "$@")
    fi
    ARCHIVES="$ARCHIVES $(basename "$zip_path")"
}

# write_readme <template> <dir> [binary] [crlf]: writes <dir>/README.txt from
# scripts/package-readme/<template>.txt, with CRLF endings if "crlf" is given
write_readme() {
    eol='\n'
    [ "${4:-}" = crlf ] && eol='\r\n'
    awk -v version="$VERSION" -v binary="${3:-}" -v eol="$eol" '
        { sub(/\r$/, ""); gsub(/@VERSION@/, version); gsub(/@BINARY@/, binary); printf "%s%s", $0, eol }
    ' "$REPO/scripts/package-readme/$1.txt" > "$2/README.txt"
}

go_build() { # <goos> <goarch> <output file>
    (cd "$REPO/src/go" && CGO_ENABLED=0 GOOS=$1 GOARCH=$2 go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$3" .)
}

# --- PowerShell version ---------------------------------------------------

# Each archive's files go in a folder named after the archive
echo "Packaging the PowerShell version ($VERSION)"
folder=system-dashboard-$VERSION-powershell
PS_DIR="$STAGE/powershell/$folder"
mkdir -p "$PS_DIR"
cp "$REPO/src/powershell/start.cmd" "$REPO/src/powershell/server.ps1" "$PS_DIR/"
cp -R "$REPO/src/powershell/modules" "$REPO/src/powershell/www" "$PS_DIR/"
printf '%s\n' "$VERSION" > "$PS_DIR/VERSION"   # read by server.ps1 -Version
write_readme powershell "$PS_DIR" "" crlf
make_zip "$OUT/$folder.zip" "$STAGE/powershell" "$folder"

# --- Go binaries ----------------------------------------------------------

if [ -n "$SKIP_GO" ]; then
    echo "Skipping the Go binaries (-n)"
else
    echo "Running Go vet and tests"
    (cd "$REPO/src/go" && go vet ./... && go test ./...)

    echo "Building windows/amd64"
    folder=system-dashboard-$VERSION-windows-amd64
    win_dir="$STAGE/windows-amd64/$folder"
    mkdir -p "$win_dir"
    go_build windows amd64 "$win_dir/system-dashboard.exe"
    write_readme windows "$win_dir" "" crlf
    make_zip "$OUT/$folder.zip" "$STAGE/windows-amd64" "$folder"

    for arch in amd64 arm64; do
        echo "Building linux/$arch"
        name=system-dashboard-linux-$arch
        folder=system-dashboard-$VERSION-linux-$arch
        linux_dir="$STAGE/linux-$arch/$folder"
        mkdir -p "$linux_dir"
        go_build linux "$arch" "$linux_dir/$name"
        chmod 755 "$linux_dir" "$linux_dir/$name"
        write_readme linux "$linux_dir" "$name"
        chmod 644 "$linux_dir/README.txt"
        tar -czf "$OUT/$folder.tar.gz" -C "$STAGE/linux-$arch" "$folder"
        ARCHIVES="$ARCHIVES $folder.tar.gz"
    done
fi

# --- Checksums ------------------------------------------------------------

# shellcheck disable=SC2086  # ARCHIVES is a space-separated list of plain file names
if has sha256sum; then
    (cd "$OUT" && sha256sum $ARCHIVES > SHA256SUMS)
else
    (cd "$OUT" && shasum -a 256 $ARCHIVES > SHA256SUMS)
fi

echo
echo "Packages in $OUT:"
# shellcheck disable=SC2086
(cd "$OUT" && ls -l $ARCHIVES SHA256SUMS)
