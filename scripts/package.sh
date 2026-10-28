#!/bin/sh
# ---------------------------------------------------------------
#  package.sh
#  Packages the system dashboard for copying to target machines.
#
#  Writes one archive per target to the output folder, containing
#  only the files the target needs (see "Copying the dashboard to
#  another machine" in README.md):
#
#    system-dashboard-<version>-powershell.zip      PowerShell version: system-dashboard/ folder
#    system-dashboard-<version>-windows-amd64.zip   system-dashboard.exe
#    system-dashboard-<version>-linux-amd64.tar.gz  system-dashboard-linux-amd64, executable
#    system-dashboard-<version>-linux-arm64.tar.gz  system-dashboard-linux-arm64, executable
#    SHA256SUMS                                     checksums, for sha256sum -c
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
#        binaries with -version. Default: git describe
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

# make_zip <zip path> <dir> <entry>: zips <entry> inside <dir>, stored as <entry>
make_zip() {
    if has zip; then
        (cd "$2" && zip -qr "$1" "$3")
    elif has bsdtar; then
        bsdtar -a -cf "$1" -C "$2" "$3"
    else
        (cd "$2" && python3 -m zipfile -c "$1" "$3")
    fi
    ARCHIVES="$ARCHIVES $(basename "$1")"
}

go_build() { # <goos> <goarch> <output file>
    (cd "$REPO/src/go" && CGO_ENABLED=0 GOOS=$1 GOARCH=$2 go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$3" .)
}

# --- PowerShell version ---------------------------------------------------

echo "Packaging the PowerShell version ($VERSION)"
PS_DIR="$STAGE/powershell/system-dashboard"
mkdir -p "$PS_DIR"
cp "$REPO/src/powershell/start.cmd" "$REPO/src/powershell/server.ps1" "$PS_DIR/"
cp -R "$REPO/src/powershell/modules" "$REPO/src/powershell/www" "$PS_DIR/"
make_zip "$OUT/system-dashboard-$VERSION-powershell.zip" "$STAGE/powershell" system-dashboard

# --- Go binaries ----------------------------------------------------------

if [ -n "$SKIP_GO" ]; then
    echo "Skipping the Go binaries (-n)"
else
    echo "Running Go vet and tests"
    (cd "$REPO/src/go" && go vet ./... && go test ./...)

    echo "Building windows/amd64"
    mkdir -p "$STAGE/windows-amd64"
    go_build windows amd64 "$STAGE/windows-amd64/system-dashboard.exe"
    make_zip "$OUT/system-dashboard-$VERSION-windows-amd64.zip" "$STAGE/windows-amd64" system-dashboard.exe

    for arch in amd64 arm64; do
        echo "Building linux/$arch"
        name=system-dashboard-linux-$arch
        mkdir -p "$STAGE/linux-$arch"
        go_build linux "$arch" "$STAGE/linux-$arch/$name"
        chmod 755 "$STAGE/linux-$arch/$name"
        tar -czf "$OUT/system-dashboard-$VERSION-linux-$arch.tar.gz" -C "$STAGE/linux-$arch" "$name"
        ARCHIVES="$ARCHIVES system-dashboard-$VERSION-linux-$arch.tar.gz"
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
