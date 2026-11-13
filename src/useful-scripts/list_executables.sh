#!/bin/sh
# ---------------------------------------------------------------
#  list_executables.sh
#  Lists the executable files on the local disks on Linux or macOS
#  (name, directory, size, last modified time and category), tagged
#  with the host name and current timestamp.
#  See docs/spec/list_executables.md and docs/spec/macos.md.
#
#  Each file is in one category. On Linux:
#    Executable  an ELF program: a regular file with any execute
#                permission bit set that starts with "\177ELF" (or
#                can't be read)
#    Library     a dynamic library: a regular file named *.so or
#                *.so.*, whatever its permissions
#    Script      a file with an execute bit that starts with "#!"
#    Installer   a package or installer: a regular file named *.deb,
#                *.rpm or *.run, whatever its permissions
#    Other       any other file with an execute bit
#  On macOS:
#    Executable  a Mach-O program: a file with an execute bit that
#                starts with a Mach-O or universal binary signature (or
#                can't be read)
#    Library     a file named *.dylib or *.so, whatever its
#                permissions, or a framework's binary with an execute
#                bit (Foo.framework/Foo or Foo.framework/Versions/*/Foo)
#    Script      a file with an execute bit that starts with "#!"
#    Installer   a file named *.pkg, *.mpkg or *.dmg, whatever its
#                permissions
#    Other       any other file with an execute bit, including Java
#                *.class files, which share the universal signature
#  Only executables are listed by default; choose others with -c.
#
#  Local disks on Linux are the filesystems on a /dev/ block device,
#  plus ZFS: network mounts, tmpfs and virtual filesystems such as
#  /proc are left out. On macOS they are the volumes that macOS marks
#  as local, except its own support volumes (VM, Preboot, Update, ...)
#  and Time Machine snapshots; files on the data volume are shown under
#  their usual paths (/Users, /Applications, ...), using the firmlinks
#  in /usr/share/firmlinks. Each filesystem is searched once, without
#  crossing into others. Folders that can't be read are skipped, so run
#  it as root to see everything.
#
#  Usage:  list_executables.sh [-f text|csv|json|html] [-o output_file] [-a] [-c categories] [-p folder]... [-n]
#    -f  Output format. Default: text.
#    -o  File to write to. Default: stdout.
#    -a  Also search network and other mounted filesystems, except
#        virtual ones such as /proc and /sys.
#    -c  Comma-separated categories to list: executable, library,
#        script, installer, other, or all. Default: executable.
#    -p  Search this folder instead of the local disks (repeatable).
#        It is searched without crossing into other filesystems.
#    -n  Leave out the host name and timestamp.
# ---------------------------------------------------------------

# Refuse to be sourced: set -eu, trap and exit would leak into the caller's shell
if { [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$0}" != "$0" ]; } ||
    case "${ZSH_EVAL_CONTEXT:-}" in *:file*) true ;; *) false ;; esac; then
    echo "Run this script instead of sourcing it: sh list_executables.sh [options]" >&2
    return 1
fi

set -eu

usage() {
    echo "Usage: $(basename "$0") [-f text|csv|json|html] [-o output_file] [-a] [-c categories] [-p folder]... [-n]" >&2
    exit 2
}

TAB=$(printf '\t')
OS=$(uname -s)
ROOTS=$(mktemp)
TMPFILE=$(mktemp)
trap 'rm -f "$ROOTS" "$TMPFILE"' EXIT INT TERM

FORMAT=text
OUT=
ALL=0
CATEGORIES=executable
TAG=1
while getopts "f:o:ac:p:nh" opt; do
    case "$opt" in
        f) FORMAT=$OPTARG ;;
        o) OUT=$OPTARG ;;
        a) ALL=1 ;;
        n) TAG=0 ;;
        c) CATEGORIES=$OPTARG ;;
        p)
            # Absolute, so the Directory column is too
            dir=$(cd "$OPTARG" 2>/dev/null && pwd) || { echo "Not a folder: $OPTARG" >&2; exit 2; }
            printf '%s\n' "$dir" >>"$ROOTS"
            ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

case "$FORMAT" in
    text|csv|json|html) ;;
    *) echo "Invalid format: $FORMAT" >&2; usage ;;
esac

# The categories to list, as " Executable Library ... " (a space before and
# after each, so a category can be matched as " <name> ")
WANT=" "
for c in $(printf '%s' "$CATEGORIES" | tr ',' ' '); do
    case "$c" in
        executable) WANT="$WANT Executable " ;;
        library) WANT="$WANT Library " ;;
        script) WANT="$WANT Script " ;;
        installer) WANT="$WANT Installer " ;;
        other) WANT="$WANT Other " ;;
        all) WANT=" Executable Library Script Installer Other " ;;
        *) echo "Invalid category: $c" >&2; usage ;;
    esac
done
[ "$WANT" != " " ] || { echo "No category given" >&2; usage; }

wants() {
    case "$WANT" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# macOS: prints the mount points to search, one per line, from mount, whose
# lines are "<device> on <mount point> (<type>, <option>, ...)". Local volumes
# are those with the "local" option, unless -a. A volume mounted more than
# once is listed once.
mac_mount_points() {
    mount | awk -v all="$ALL" '
        {
            on = index($0, " on ")
            paren = 0
            for (i = length($0); i > on; i--) if (substr($0, i, 2) == " (") { paren = i; break }
            if (!on || !paren) next
            device = substr($0, 1, on - 1)
            point = substr($0, on + 4, paren - on - 4)
            options = ", " substr($0, paren + 2, length($0) - paren - 2) ", "
            fstype = options; sub(/^, /, "", fstype); sub(/,.*/, "", fstype)
            if (fstype == "devfs" || fstype == "autofs") next
            if (!all && index(options, ", local, ") == 0) next
            # macOS support volumes, and Time Machine snapshots, which repeat
            # the files of the volume they were taken from
            if (point ~ /^\/System\/Volumes\/(VM|Preboot|Recovery|Update|xarts|iSCPreboot|Hardware)(\/|$)/) next
            if (point ~ /^\/Volumes\/(\.timemachine|com\.apple\.TimeMachine\.)/) next
            if (!seen[device]++) print point
        }
    '
}

# Prints the mount points to search, one per line, from /proc/self/mountinfo.
# A filesystem mounted more than once (e.g. bind mounts) is listed once.
mount_points() {
    if [ "$OS" = Darwin ]; then
        mac_mount_points
        return
    fi
    if [ ! -r /proc/self/mountinfo ]; then
        echo /
        return
    fi
    awk -v all="$ALL" '
        # Mount points escape space, tab, newline and backslash as octal
        function unescape(s) {
            gsub(/\\040/, " ", s); gsub(/\\011/, "\t", s)
            gsub(/\\012/, "\n", s); gsub(/\\134/, "\\", s)
            return s
        }
        {
            # Optional fields end with "-", then filesystem type and source
            for (i = 7; i <= NF && $i != "-"; i++) ;
            fstype = $(i + 1); source = $(i + 2)
            if (fstype ~ /^(proc|sysfs|devtmpfs|devpts|tmpfs|ramfs|cgroup2?|securityfs|debugfs|tracefs|pstore|bpf|mqueue|hugetlbfs|configfs|fusectl|autofs|binfmt_misc|rpc_pipefs|nsfs|efivarfs|selinuxfs)$/) next
            if (!all && source !~ /^\/dev\// && fstype != "zfs") next
            key = $3 " " $4   # device and the folder of it that is mounted
            if (!seen[key]++) print unescape($5)
        }
    ' /proc/self/mountinfo
}

[ -s "$ROOTS" ] || mount_points >"$ROOTS"

HOST=$(uname -n)
# ISO 8601, local time with its time-zone offset (+0800 -> +08:00): when the
# search started, as the dashboard does
NOW=$(date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)$/:\1/')

# BusyBox stat leaves the time-zone offset out of %y, so use the current one
# (it can be an hour off for files dated on the other side of a DST change)
NOW_ZONE=$(date +%z)

# Prints "size modified path" for the files under folder $1 that may be in
# the chosen categories: libraries and installers by name (they often have
# no execute bit), and other files by their execute bits
find_files() {
    set -- "$1" -xdev -type f \(
    or=
    if wants Library; then
        if [ "$OS" = Darwin ]; then
            # A framework's binary has no extension, so files with an execute
            # bit inside a framework are checked by path later
            set -- "$@" -name '*.dylib' -o -name '*.so' -o \
                \( -path '*.framework/*' \( -perm -u=x -o -perm -g=x -o -perm -o=x \) \)
        else
            set -- "$@" -name '*.so' -o -name '*.so.*'
        fi
        or=-o
    fi
    if wants Installer; then
        if [ "$OS" = Darwin ]; then
            set -- "$@" $or -name '*.pkg' -o -name '*.mpkg' -o -name '*.dmg'
        else
            set -- "$@" $or -name '*.deb' -o -name '*.rpm' -o -name '*.run'
        fi
        or=-o
    fi
    if wants Executable || wants Script || wants Other; then
        set -- "$@" $or -perm -u=x -o -perm -g=x -o -perm -o=x
    fi
    if [ "$OS" = Darwin ]; then
        # BSD stat: "size YYYY-MM-DD HH:MM:SS +ZZZZ path"
        find "$@" \) -exec stat -f '%z %Sm %N' -t '%Y-%m-%d %H:%M:%S %z' {} +
    else
        find "$@" \) -exec stat -c '%s %y %n' {} +
    fi
}

# Each file as "name<TAB>directory<TAB>size<TAB>modified<TAB>category",
# sorted by directory and name. stat %y is
# "YYYY-MM-DD HH:MM:SS[.frac] [+ZZZZ]", which becomes ISO 8601:
# YYYY-MM-DDTHH:MM:SS+ZZ:ZZ.
while IFS= read -r root; do
    find_files "$root" 2>/dev/null || true
done <"$ROOTS" | LC_ALL=C awk -v OFS="$TAB" -v now_zone="$NOW_ZONE" -v want="$WANT" -v os="$OS" '
    BEGIN {
        # macOS firmlinks, as "/Users<TAB>Users": the folder on the system
        # volume, then the folder on the data volume that it shows
        if (os == "Darwin") {
            while ((getline line < "/usr/share/firmlinks") > 0) {
                split(line, part, "\t")
                if (part[1] != "" && part[2] != "") firmlink["/System/Volumes/Data/" part[2]] = part[1]
            }
            close("/usr/share/firmlinks")
        }
    }
    # The usual path of a file on the macOS data volume: the longest firmlink
    # that the path is inside, e.g. /System/Volumes/Data/Users/x -> /Users/x
    function usual_path(p,    target, best) {
        best = ""
        for (target in firmlink)
            if ((p == target || substr(p, 1, length(target) + 1) == target "/") && length(target) > length(best))
                best = target
        return best == "" ? p : firmlink[best] substr(p, length(best) + 1)
    }
    # True if name is the binary of the framework that dir is in:
    # Foo.framework/Foo or Foo.framework/Versions/<version>/Foo
    function framework_binary(dir, name,    fw) {
        fw = dir
        sub(/\/Versions\/[^\/]+$/, "", fw)
        if (fw !~ /\.framework$/) return 0
        sub(/.*\//, "", fw)
        return fw == name ".framework"
    }
    {
        size = $1; date = $2; time = $3
        file = $0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", file)
        zone = now_zone
        if (file ~ /^[+-][0-9][0-9][0-9][0-9] /) {
            zone = substr(file, 1, 5)
            file = substr(file, 7)
        }
        zone = substr(zone, 1, 3) ":" substr(zone, 4, 2)
        sub(/\..*/, "", time)
        path = (os == "Darwin") ? usual_path(file) : file
        name = path; sub(/.*\//, "", name)
        dir = path; sub(/\/[^\/]*$/, "", dir)
        if (dir == "") dir = "/"
        if (os == "Darwin" && (name ~ /\.(dylib|so)$/ || framework_binary(dir, name))) {
            category = "Library"
        } else if (os == "Darwin" && name ~ /\.(pkg|mpkg|dmg)$/) {
            category = "Installer"
        } else if (os == "Darwin" && name ~ /\.class$/) {
            # Java class files start like a universal binary
            category = "Other"
        } else if (os != "Darwin" && name ~ /\.so(\.|$)/) {
            category = "Library"
        } else if (os != "Darwin" && name ~ /\.(deb|rpm|run)$/) {
            category = "Installer"
        } else {
            # An ELF program starts with "\177ELF", a Mach-O program with
            # FEEDFACE or FEEDFACF in either byte order, a universal binary
            # with CAFEBABE or CAFEBABF, and a script with "#!". A file that
            # cannot be read is most likely a program.
            first = ""
            status = (getline first < file)
            close(file)
            magic = substr(first, 1, 4)
            if (status < 0) category = "Executable"
            else if (os != "Darwin" && magic == "\177ELF") category = "Executable"
            else if (os == "Darwin" && (magic == "\376\355\372\316" || magic == "\376\355\372\317" ||
                magic == "\316\372\355\376" || magic == "\317\372\355\376" ||
                magic == "\312\376\272\276" || magic == "\312\376\272\277")) category = "Executable"
            else if (substr(first, 1, 2) == "#!") category = "Script"
            else category = "Other"
        }
        if (index(want, " " category " ")) print name, dir, size, date "T" time zone, category
    }
' | LC_ALL=C sort -t "$TAB" -k2,2 -k1,1 -u >"$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    echo "No executable files found." >&2
    exit 1
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
        {
            n++
            name[n] = $1; dir[n] = $2; size[n] = $3; mod[n] = $4; cat[n] = $5
            if (length($1) > wn) wn = length($1)
            if (length($2) > wd) wd = length($2)
            if (length($3) > ws) ws = length($3)
        }
        END {
            if (fmt == "text") {
                if (tag) {
                    print "Host Name: " host
                    print "Timestamp: " now
                    print ""
                }
                if (wn < 4) wn = 4
                if (wd < 9) wd = 9
                if (ws < 4) ws = 4
                f = "%-" wn "s  %-" wd "s  %" ws "s  %-25s  %s\n"
                printf f, "Name", "Directory", "Size", "Modified", "Category"
                printf f, "----", "---------", "----", "--------", "--------"
                for (i = 1; i <= n; i++) printf f, name[i], dir[i], size[i], mod[i], cat[i]
            } else if (fmt == "csv") {
                # One table only, so the host tag goes in extra columns on each row
                pre = tag ? csv(host) "," csv(now) "," : ""
                print (tag ? "\"HostName\",\"Timestamp\"," : "") "\"Name\",\"Directory\",\"Size\",\"Modified\",\"Category\""
                for (i = 1; i <= n; i++)
                    print pre csv(name[i]) "," csv(dir[i]) "," csv(size[i]) "," csv(mod[i]) "," csv(cat[i])
            } else if (fmt == "json") {
                ind = ""
                if (tag) {
                    print "{"
                    printf "  \"HostName\": %s,\n", json(host)
                    printf "  \"Timestamp\": %s,\n", json(now)
                    printf "  \"Executables\": "
                    ind = "  "
                }
                print "["
                for (i = 1; i <= n; i++)
                    printf "%s  {\"Name\": %s, \"Directory\": %s, \"Size\": %s, \"Modified\": %s, \"Category\": %s}%s\n",
                        ind, json(name[i]), json(dir[i]), size[i], json(mod[i]), json(cat[i]), (i < n ? "," : "")
                print ind "]"
                if (tag) print "}"
            } else if (fmt == "html") {
                t = "Executable files" (tag ? " on " html(host) : "")
                print "<!DOCTYPE html>"
                print "<html><head><meta charset=\"utf-8\"><title>" t "</title></head><body>"
                print "<h1>" t "</h1>"
                if (tag) {
                    print "<table>"
                    print "<tr><th>Host Name</th><td>" html(host) "</td></tr>"
                    print "<tr><th>Timestamp</th><td>" html(now) "</td></tr>"
                    print "</table>"
                }
                print "<p>" n " files</p>"
                print "<table>"
                print "<tr><th>Name</th><th>Directory</th><th>Size</th><th>Modified</th><th>Category</th></tr>"
                for (i = 1; i <= n; i++)
                    print "<tr><td>" html(name[i]) "</td><td>" html(dir[i]) "</td><td>" size[i] "</td><td>" html(mod[i]) "</td><td>" cat[i] "</td></tr>"
                print "</table>"
                print "</body></html>"
            }
        }
    ' "$TMPFILE"
}

if [ -n "$OUT" ]; then
    format_output >"$OUT"
    echo "Saved $(wc -l <"$TMPFILE" | tr -d ' ') files to: $OUT" >&2
else
    format_output
fi
