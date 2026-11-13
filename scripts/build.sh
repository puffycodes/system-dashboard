#!/bin/sh
# ---------------------------------------------------------------
#  build.sh
#  Builds the Go version of the dashboard as single executables.
#
#  Builds one binary per target with the same flags as package.sh,
#  without running the tests or making archives. The web UI is
#  embedded, so each binary can be copied and run on its own.
#  Existing files are replaced. Each binary prints its version with
#  -version: the -v given, or git describe as in package.sh.
#
#    windows-amd64   src/go/system-dashboard.exe
#    linux-amd64     src/go/system-dashboard-linux-amd64
#    linux-arm64     src/go/system-dashboard-linux-arm64
#    darwin-arm64    src/go/system-dashboard-darwin-arm64
#    darwin-amd64    src/go/system-dashboard-darwin-amd64
#
#  Go's linker signs the darwin-arm64 binary ad hoc, which Apple
#  silicon requires, so it can be built on any OS.
#
#  Usage:  build.sh [-t target]... [-o output_file] [-v version]
#          build.sh -c
#    -t  windows-amd64, linux-amd64, linux-arm64, darwin-arm64,
#        darwin-amd64 or all. Repeat for several targets. Default:
#        the binary for this machine's OS (Linux or macOS) and CPU,
#        e.g. linux-amd64 or darwin-arm64.
#    -o  Path of the binary, instead of the default in src/go.
#        Only with one target.
#    -v  Version the binaries report with -version. Default: git
#        describe --tags --always --dirty, or "dev" outside a git
#        checkout.
#    -c  Remove the binaries from src/go instead of building. Files
#        written elsewhere with -o are left alone.
# ---------------------------------------------------------------

# Refuse to be sourced: set -eu and exit would leak into the caller's shell
if { [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$0}" != "$0" ]; } ||
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) true ;; *) false ;; esac; then
    echo "Run this script instead of sourcing it: sh build.sh [options]" >&2
    return 1
fi

set -eu

usage() {
    echo "Usage: $(basename "$0") [-t target]... [-o output_file] [-v version]" >&2
    echo "       $(basename "$0") -c" >&2
    exit 2
}

ALL_TARGETS="windows-amd64 linux-amd64 linux-arm64 darwin-arm64 darwin-amd64"

REPO=$(cd "$(dirname "$0")/.." && pwd)
GO_SRC=$REPO/src/go
TARGETS=
OUT_FILE=
VERSION=
CLEAN=
while getopts "t:o:v:ch" opt; do
    case "$opt" in
        t)
            case "$OPTARG" in
                all) TARGETS="$TARGETS $ALL_TARGETS" ;;
                windows-amd64 | linux-amd64 | linux-arm64 | darwin-arm64 | darwin-amd64) TARGETS="$TARGETS $OPTARG" ;;
                *) echo "Unknown target: $OPTARG (use windows-amd64, linux-amd64, linux-arm64, darwin-arm64, darwin-amd64 or all)" >&2; usage ;;
            esac
            ;;
        o) OUT_FILE=$OPTARG ;;
        v) VERSION=$OPTARG ;;
        c) CLEAN=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

has() { command -v "$1" >/dev/null 2>&1; }
die() { echo "$*" >&2; exit 1; }

file_name() { # <target>
    case "$1" in
        windows-amd64) echo system-dashboard.exe ;;
        *) echo "system-dashboard-$1" ;;
    esac
}

# --- Clean ----------------------------------------------------------------

if [ -n "$CLEAN" ]; then
    [ -z "$TARGETS" ] && [ -z "$OUT_FILE" ] && [ -z "$VERSION" ] || die "-c can't be combined with -t, -o or -v."
    removed=0
    for t in $ALL_TARGETS; do
        file=$GO_SRC/$(file_name "$t")
        if [ -e "$file" ]; then
            rm -f "$file"
            echo "Removed $file"
            removed=$((removed + 1))
        fi
    done
    [ "$removed" -gt 0 ] || echo "Nothing to clean."
    exit 0
fi

# --- Build ----------------------------------------------------------------

has go || die "Go not found. Install Go 1.20+ to build the executables."

if [ -z "$TARGETS" ]; then
    os=linux
    [ "$(uname -s)" = Darwin ] && os=darwin
    case "$(uname -m)" in
        aarch64 | arm64) TARGETS=$os-arm64 ;;
        *) TARGETS=$os-amd64 ;;
    esac
fi

# Drop duplicates, keeping the order
unique=
for t in $TARGETS; do
    case " $unique " in *" $t "*) ;; *) unique="$unique $t" ;; esac
done
TARGETS=$unique

if [ -n "$OUT_FILE" ]; then
    # shellcheck disable=SC2086  # TARGETS is a space-separated list of target names
    set -- $TARGETS
    [ $# -eq 1 ] || die "-o can only be used with a single -t target."
    mkdir -p "$(dirname "$OUT_FILE")"
    OUT_FILE=$(cd "$(dirname "$OUT_FILE")" && pwd)/$(basename "$OUT_FILE")
fi

if [ -z "$VERSION" ]; then
    VERSION=$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null) || VERSION=dev
fi
VERSION=$(printf '%s' "$VERSION" | tr -c 'A-Za-z0-9._+-' '-')   # same as package.sh; also keeps -ldflags intact

BUILT=
UNIX_BUILT=
for t in $TARGETS; do
    goos=${t%-*}
    goarch=${t#*-}
    out=${OUT_FILE:-$GO_SRC/$(file_name "$t")}
    echo "Building $goos/$goarch ($VERSION)"
    # Set the target explicitly, so GOOS/GOARCH in the environment don't apply
    (cd "$GO_SRC" && CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -trimpath -ldflags "-s -w -X main.version=$VERSION" -o "$out" .)
    if [ "$goos" != windows ]; then
        chmod 755 "$out"
        UNIX_BUILT=1
    fi
    BUILT="$BUILT
$out"
done

echo
printf '%s\n' "$BUILT" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    size=$(( ($(wc -c < "$file") + 1023) / 1024 ))
    echo "Built $file ($size KB)"
done
if [ -n "$UNIX_BUILT" ]; then
    echo "The Linux and macOS binaries are executable. If you copy one through Windows or a USB stick, run chmod +x on it again."
fi
