#!/bin/sh
# ---------------------------------------------------------------
#  list_installed_software.sh
#  Lists installed software (name + version) on Linux or macOS, tagged
#  with the host name and current timestamp. The host's IP addresses
#  are listed by list_host_information.sh.
#  See docs/spec/list_installed_software.md and docs/spec/macos.md.
#
#  Sources on Linux: the native package manager (dpkg, rpm, pacman or
#  apk, first one found), plus Flatpak apps and Snaps when present.
#  Sources on macOS: the .app bundles in /Applications and
#  ~/Applications (except the apps that come with macOS), plus
#  Homebrew formulae and casks when Homebrew is installed.
#
#  Usage:  list_installed_software.sh [-f text|csv|json|html] [-o output_file] [-n]
#          Default format is text; default output is stdout.
#          -n leaves out the host name and timestamp.
# ---------------------------------------------------------------

# Refuse to be sourced: set -eu, trap and exit would leak into the caller's shell
if { [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$0}" != "$0" ]; } ||
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) true ;; *) false ;; esac; then
    echo "Run this script instead of sourcing it: sh list_installed_software.sh [options]" >&2
    return 1
fi

set -eu

usage() {
    echo "Usage: $(basename "$0") [-f text|csv|json|html] [-o output_file] [-n]" >&2
    exit 2
}

FORMAT=text
OUT=
TAG=1
while getopts "f:o:nh" opt; do
    case "$opt" in
        f) FORMAT=$OPTARG ;;
        o) OUT=$OPTARG ;;
        n) TAG=0 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

case "$FORMAT" in
    text|csv|json|html) ;;
    *) echo "Invalid format: $FORMAT" >&2; usage ;;
esac

has() { command -v "$1" >/dev/null 2>&1; }

TAB=$(printf '\t')
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT INT TERM

# macOS: "name<TAB>version" for each .app bundle in /Applications and
# ~/Applications, and their subfolders, but not for apps inside other apps
# (-prune). The apps that come with macOS are on the read-only system
# volume, so an app on the same volume as /System/Applications is skipped.
mac_apps() {
    sysdev=$(stat -f %d /System/Applications 2>/dev/null) || sysdev=
    for dir in /Applications "${HOME:-/nonexistent}/Applications"; do
        [ -d "$dir" ] || continue
        find "$dir" -name '*.app' -type d -prune -exec stat -f '%d%t%N' {} + 2>/dev/null || true
    done | awk -F"$TAB" -v sysdev="$sysdev" '$1 != sysdev { print $2 }' |
        while IFS= read -r app; do
            name=${app##*/}
            name=${name%.app}
            plist=$app/Contents/Info.plist
            version=$(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null) ||
                version=$(plutil -extract CFBundleVersion raw -o - "$plist" 2>/dev/null) ||
                version=
            printf '%s\t%s\n' "$name" "$version"
        done
}

# macOS: "name<TAB>version" for each Homebrew formula and cask, the same as
# brew list --versions and brew list --cask --versions, but read from the
# Cellar and Caskroom folders: brew itself is slow to start and refuses to
# run as root. Apple silicon uses /opt/homebrew, Intel /usr/local; a Mac can
# have both. When several versions are installed, the latest is listed.
mac_homebrew() {
    for prefix in "${HOMEBREW_PREFIX:-}" /opt/homebrew /usr/local; do
        [ -n "$prefix" ] || continue
        for kind in Cellar Caskroom; do
            for version_dir in "$prefix/$kind"/*/*/; do
                [ -d "$version_dir" ] || continue
                version_dir=${version_dir%/}
                version=${version_dir##*/}
                name=${version_dir%/*}
                name=${name##*/}
                case "$name$version" in .*) continue ;; esac   # e.g. .metadata
                printf '%s\t%s\n' "$name" "$version"
            done
        done
    done | awk -F"$TAB" '
        # 1 if version a is later than b: numeric parts are compared as
        # numbers, other parts as text (1.10 > 1.9, 2.0_1 > 2.0)
        function later(a, b,    na, nb, pa, pb, i) {
            na = split(a, pa, /[^0-9A-Za-z]+/)
            nb = split(b, pb, /[^0-9A-Za-z]+/)
            for (i = 1; i <= na && i <= nb; i++) {
                if (pa[i] == pb[i]) continue
                if (pa[i] ~ /^[0-9]+$/ && pb[i] ~ /^[0-9]+$/) return pa[i] + 0 > pb[i] + 0
                return pa[i] > pb[i]
            }
            return na > nb
        }
        !($1 in latest) || later($2, latest[$1]) { latest[$1] = $2 }
        END { for (name in latest) print name "\t" latest[name] }
    '
}

# Each source writes "name<TAB>version" lines to stdout
{
    if [ "$(uname -s)" = Darwin ]; then
        mac_apps
        mac_homebrew
    elif has dpkg-query; then
        dpkg-query -W -f='${Status}\t${Package}\t${Version}\n' 2>/dev/null |
            awk -F'\t' '$1 ~ / installed$/ { print $2 "\t" $3 }'
    elif has rpm; then
        rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null
    elif has pacman; then
        pacman -Q 2>/dev/null | awk '{ print $1 "\t" $2 }'
    elif has apk; then
        # "name-1.2.3-r0" -> name, 1.2.3-r0
        apk info -v 2>/dev/null |
            sed -n "s/^\(.*\)-\([^-]*-r[0-9][0-9]*\)\$/\1$TAB\2/p"
    fi

    if has flatpak; then
        flatpak list --app --columns=name,version 2>/dev/null
    fi

    # snap blocks when snapd isn't running (e.g. WSL without systemd)
    if has snap && [ -S /run/snapd.socket ]; then
        snap list 2>/dev/null | awk 'NR > 1 { print $1 "\t" $2 }'
    fi
} | LC_ALL=C sort -u >"$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    echo "No installed software found." >&2
    exit 1
fi

HOST=
NOW=
if [ "$TAG" = 1 ]; then
    HOST=$(uname -n)
    # ISO 8601, local time with its time-zone offset (+0800 -> +08:00)
    NOW=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/')
fi

format_output() {
    awk -F"$TAB" -v fmt="$FORMAT" -v tag="$TAG" -v host="$HOST" -v now="$NOW" '
        function json(s) {
            gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
            gsub(/\r/, "\\r", s);  gsub(/\n/, "\\n", s)
            return "\"" s "\""
        }
        function csv(s) {
            gsub(/"/, "\"\"", s)
            return "\"" s "\""
        }
        function html(s) {
            gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s)
            gsub(/>/, "\\&gt;", s);  gsub(/"/, "\\&quot;", s)
            return s
        }
        $1 != "" {
            n++
            name[n] = $1
            ver[n] = ($2 == "") ? "N/A" : $2
            if (length($1) > w) w = length($1)
        }
        END {
            if (fmt == "text") {
                if (tag) {
                    print "Host Name: " host
                    print "Timestamp: " now
                    print ""
                }
                if (w < 4) w = 4
                f = "%-" w "s  %s\n"
                printf f, "Name", "Version"
                printf f, "----", "-------"
                for (i = 1; i <= n; i++) printf f, name[i], ver[i]
            } else if (fmt == "csv") {
                # One table only, so the host tag goes in extra columns on each row
                pre = tag ? csv(host) "," csv(now) "," : ""
                print (tag ? "\"HostName\",\"Timestamp\"," : "") "\"Name\",\"Version\""
                for (i = 1; i <= n; i++) print pre csv(name[i]) "," csv(ver[i])
            } else if (fmt == "json") {
                ind = ""
                if (tag) {
                    print "{"
                    printf "  \"HostName\": %s,\n", json(host)
                    printf "  \"Timestamp\": %s,\n", json(now)
                    printf "  \"Software\": "
                    ind = "  "
                }
                print "["
                for (i = 1; i <= n; i++)
                    printf "%s  {\"Name\": %s, \"Version\": %s}%s\n",
                        ind, json(name[i]), json(ver[i]), (i < n ? "," : "")
                print ind "]"
                if (tag) print "}"
            } else if (fmt == "html") {
                t = "Installed software" (tag ? " on " html(host) : "")
                print "<!DOCTYPE html>"
                print "<html><head><meta charset=\"utf-8\"><title>" t "</title></head><body>"
                print "<h1>" t "</h1>"
                if (tag) {
                    print "<table>"
                    print "<tr><th>Host Name</th><td>" html(host) "</td></tr>"
                    print "<tr><th>Timestamp</th><td>" html(now) "</td></tr>"
                    print "</table>"
                }
                print "<p>" n " items</p>"
                print "<table>"
                print "<tr><th>Name</th><th>Version</th></tr>"
                for (i = 1; i <= n; i++)
                    print "<tr><td>" html(name[i]) "</td><td>" html(ver[i]) "</td></tr>"
                print "</table>"
                print "</body></html>"
            }
        }
    ' "$TMPFILE"
}

if [ -n "$OUT" ]; then
    format_output >"$OUT"
    echo "Saved $(wc -l <"$TMPFILE" | tr -d ' ') items to: $OUT" >&2
else
    format_output
fi
