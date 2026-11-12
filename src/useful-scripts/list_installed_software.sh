#!/bin/sh
# ---------------------------------------------------------------
#  list_installed_software.sh
#  Lists installed software (name + version) on Linux, with the host
#  name, IP addresses and current timestamp.
#  See docs/spec/list_installed_software.md.
#
#  Sources: the native package manager (dpkg, rpm, pacman or apk,
#  first one found), plus Flatpak apps and Snaps when present.
#
#  Usage:  list_installed_software.sh [-f text|csv|json|html] [-o output_file] [-n]
#          Default format is text; default output is stdout.
#          -n leaves out the host name, IP addresses and timestamp.
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
SYSINFO=1
while getopts "f:o:nh" opt; do
    case "$opt" in
        f) FORMAT=$OPTARG ;;
        o) OUT=$OPTARG ;;
        n) SYSINFO=0 ;;
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

# Each source writes "name<TAB>version" lines to stdout
{
    if has dpkg-query; then
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

# Global addresses of the interfaces, IPv4 first, comma separated.
# Loopback and link-local addresses are skipped, as they don't
# identify the machine.
ip_addresses() {
    if has ip; then
        { ip -o -4 addr show scope global; ip -o -6 addr show scope global; } 2>/dev/null |
            awk '{ sub(/\/.*/, "", $4); print $4 }'
    elif has hostname; then
        # Not every hostname has -I (e.g. BusyBox); errors are dropped
        hostname -I 2>/dev/null | tr ' ' '\n'
    fi | awk 'NF && !seen[$0]++ { printf "%s%s", (n++ ? ", " : ""), $0 }'
}

HOST=
IPS=
NOW=
if [ "$SYSINFO" = 1 ]; then
    HOST=$(uname -n)
    IPS=$(ip_addresses) || IPS=
    [ -n "$IPS" ] || IPS=N/A
    # ISO 8601, local time with its time-zone offset (+0800 -> +08:00)
    NOW=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/')
fi

format_output() {
    awk -F"$TAB" -v fmt="$FORMAT" -v sysinfo="$SYSINFO" \
        -v host="$HOST" -v ips="$IPS" -v now="$NOW" '
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
                if (sysinfo) {
                    print "Host Name:  " host
                    print "IP Address: " ips
                    print "Timestamp:  " now
                    print ""
                }
                if (w < 4) w = 4
                f = "%-" w "s  %s\n"
                printf f, "Name", "Version"
                printf f, "----", "-------"
                for (i = 1; i <= n; i++) printf f, name[i], ver[i]
            } else if (fmt == "csv") {
                # One table only, so the system info goes in extra columns on each row
                pre = sysinfo ? csv(host) "," csv(ips) "," csv(now) "," : ""
                print (sysinfo ? "\"HostName\",\"IPAddress\",\"Timestamp\"," : "") "\"Name\",\"Version\""
                for (i = 1; i <= n; i++) print pre csv(name[i]) "," csv(ver[i])
            } else if (fmt == "json") {
                ind = ""
                if (sysinfo) {
                    print "{"
                    printf "  \"HostName\": %s,\n", json(host)
                    printf "  \"IPAddress\": ["
                    if (ips != "N/A") {
                        k = split(ips, ip, /, /)
                        for (j = 1; j <= k; j++) printf "%s%s", (j > 1 ? ", " : ""), json(ip[j])
                    }
                    print "],"
                    printf "  \"Timestamp\": %s,\n", json(now)
                    printf "  \"Software\": "
                    ind = "  "
                }
                print "["
                for (i = 1; i <= n; i++)
                    printf "%s  {\"Name\": %s, \"Version\": %s}%s\n",
                        ind, json(name[i]), json(ver[i]), (i < n ? "," : "")
                print ind "]"
                if (sysinfo) print "}"
            } else if (fmt == "html") {
                t = "Installed software" (sysinfo ? " on " html(host) : "")
                print "<!DOCTYPE html>"
                print "<html><head><meta charset=\"utf-8\"><title>" t "</title></head><body>"
                print "<h1>" t "</h1>"
                if (sysinfo) {
                    print "<table>"
                    print "<tr><th>Host Name</th><td>" html(host) "</td></tr>"
                    print "<tr><th>IP Address</th><td>" html(ips) "</td></tr>"
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
