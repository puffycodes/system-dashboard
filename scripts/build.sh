#!/bin/sh
# ---------------------------------------------------------------
#  build.sh
#  Builds the Go version of the dashboard as single executables.
#
#  Builds one binary per target with the same flags as package.sh,
#  without running the tests or making archives. The web UI is
#  embedded, so each binary can be copied and run on its own.
#  Existing files are replaced.
#
#    windows-amd64   src/go/system-dashboard.exe
#    linux-amd64     src/go/system-dashboard-linux-amd64
#    linux-arm64     src/go/system-dashboard-linux-arm64
#
#  Usage:  build.sh [-t target]... [-o output_file]
#          build.sh -c
#    -t  windows-amd64, linux-amd64, linux-arm64 or all. Repeat for
#        several targets. Default: the Linux binary for this
#        machine's CPU (linux-arm64 on ARM64, otherwise linux-amd64).
#    -o  Path of the binary, instead of the default in src/go.
#        Only with one target.
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
    echo "Usage: $(basename "$0") [-t target]... [-o output_file]" >&2
    echo "       $(basename "$0") -c" >&2
    exit 2
}

ALL_TARGETS="windows-amd64 linux-amd64 linux-arm64"

REPO=$(cd "$(dirname "$0")/.." && pwd)
GO_SRC=$REPO/src/go
TARGETS=
OUT_FILE=
CLEAN=
while getopts "t:o:ch" opt; do
    case "$opt" in
        t)
            case "$OPTARG" in
                all) TARGETS="$TARGETS $ALL_TARGETS" ;;
                windows-amd64 | linux-amd64 | linux-arm64) TARGETS="$TARGETS $OPTARG" ;;
                *) echo "Unknown target: $OPTARG (use windows-amd64, linux-amd64, linux-arm64 or all)" >&2; usage ;;
            esac
            ;;
        o) OUT_FILE=$OPTARG ;;
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
    [ -z "$TARGETS" ] && [ -z "$OUT_FILE" ] || die "-c can't be combined with -t or -o."
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
    case "$(uname -m)" in
        aarch64 | arm64) TARGETS=linux-arm64 ;;
        *) TARGETS=linux-amd64 ;;
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

BUILT=
LINUX_BUILT=
for t in $TARGETS; do
    goos=${t%-*}
    goarch=${t#*-}
    out=${OUT_FILE:-$GO_SRC/$(file_name "$t")}
    echo "Building $goos/$goarch"
    # Set the target explicitly, so GOOS/GOARCH in the environment don't apply
    (cd "$GO_SRC" && CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -trimpath -ldflags "-s -w" -o "$out" .)
    if [ "$goos" = linux ]; then
        chmod 755 "$out"
        LINUX_BUILT=1
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
if [ -n "$LINUX_BUILT" ]; then
    echo "The Linux binaries are executable. If you copy one through Windows or a USB stick, run chmod +x on it again."
fi
