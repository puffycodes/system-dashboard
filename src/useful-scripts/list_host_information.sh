#!/bin/sh
# ---------------------------------------------------------------
#  list_host_information.sh
#  Lists the information that identifies this machine on Linux:
#  host name, IP addresses and current timestamp.
#  The host name is the same as in list_installed_software.sh and
#  list_executables.sh, so their files can be matched to this host.
#  See docs/spec/list_host_information.md.
#
#  Usage:  list_host_information.sh [-f text|csv|json|html] [-o output_file]
#          Default format is text; default output is stdout.
# ---------------------------------------------------------------

# Refuse to be sourced: set -eu and exit would leak into the caller's shell
if { [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$0}" != "$0" ]; } ||
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) true ;; *) false ;; esac; then
    echo "Run this script instead of sourcing it: sh list_host_information.sh [options]" >&2
    return 1
fi

set -eu

usage() {
    echo "Usage: $(basename "$0") [-f text|csv|json|html] [-o output_file]" >&2
    exit 2
}

FORMAT=text
OUT=
while getopts "f:o:h" opt; do
    case "$opt" in
        f) FORMAT=$OPTARG ;;
        o) OUT=$OPTARG ;;
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

HOST=$(uname -n)
IPS=$(ip_addresses) || IPS=
[ -n "$IPS" ] || IPS=N/A
# ISO 8601, local time with its time-zone offset (+0800 -> +08:00)
NOW=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/')

format_output() {
    awk -v fmt="$FORMAT" -v host="$HOST" -v ips="$IPS" -v now="$NOW" '
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
        BEGIN {
            if (fmt == "text") {
                print "Host Name:    " host
                print "IP Addresses: " ips
                print "Timestamp:    " now
            } else if (fmt == "csv") {
                print "\"HostName\",\"IPAddresses\",\"Timestamp\""
                print csv(host) "," csv(ips) "," csv(now)
            } else if (fmt == "json") {
                print "{"
                printf "  \"HostName\": %s,\n", json(host)
                printf "  \"IPAddresses\": ["
                if (ips != "N/A") {
                    k = split(ips, ip, /, /)
                    for (j = 1; j <= k; j++) printf "%s%s", (j > 1 ? ", " : ""), json(ip[j])
                }
                print "],"
                printf "  \"Timestamp\": %s\n", json(now)
                print "}"
            } else if (fmt == "html") {
                t = "Host information for " html(host)
                print "<!DOCTYPE html>"
                print "<html><head><meta charset=\"utf-8\"><title>" t "</title></head><body>"
                print "<h1>" t "</h1>"
                print "<table>"
                print "<tr><th>Field</th><th>Value</th></tr>"
                print "<tr><td>Host Name</td><td>" html(host) "</td></tr>"
                print "<tr><td>IP Addresses</td><td>" html(ips) "</td></tr>"
                print "<tr><td>Timestamp</td><td>" html(now) "</td></tr>"
                print "</table>"
                print "</body></html>"
            }
        }
    '
}

if [ -n "$OUT" ]; then
    format_output >"$OUT"
    echo "Saved host information to: $OUT" >&2
else
    format_output
fi
