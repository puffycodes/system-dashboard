package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// The macOS parts of the dashboard that only parse text, compare values or
// read ordinary folders. They make no macOS calls, so they build on every OS
// and macos_test.go runs on any machine. software_darwin.go and
// executables_darwin.go use them. See docs/spec/macos.md.

var (
	// macOS's own support volumes, which list_executables.sh leaves out
	macSupportVolume = regexp.MustCompile(`^/System/Volumes/(VM|Preboot|Recovery|Update|xarts|iSCPreboot|Hardware)(/|$)`)
	// Time Machine snapshots, which repeat the files of the volume they were
	// taken from
	timeMachineSnapshot = regexp.MustCompile(`^/Volumes/(\.timemachine|com\.apple\.TimeMachine\.)`)
)

// parseMacMounts returns the mount points to search from the output of
// mount, as list_executables.sh does without -a. Its lines are
// "<device> on <mount point> (<type>, <option>, ...)", and a mount point can
// itself contain " on " or " (". Local volumes have the "local" option;
// devfs, autofs, the support volumes and Time Machine snapshots are left out.
// A device mounted more than once is listed once.
func parseMacMounts(out string) []string {
	seen := map[string]bool{}
	var roots []string
	for _, line := range strings.Split(out, "\n") {
		on := strings.Index(line, " on ")
		paren := strings.LastIndex(line, " (")
		if on < 0 || paren < on+4 || !strings.HasSuffix(line, ")") {
			continue
		}
		device := line[:on]
		point := line[on+4 : paren]
		inner := line[paren+2 : len(line)-1] // "<type>, <option>, ..."
		options := ", " + inner + ", "
		fstype := strings.SplitN(inner, ",", 2)[0]
		switch {
		case fstype == "devfs" || fstype == "autofs":
		case !strings.Contains(options, ", local, "):
		case macSupportVolume.MatchString(point) || timeMachineSnapshot.MatchString(point):
		case !seen[device]:
			seen[device] = true
			roots = append(roots, point)
		}
	}
	return roots
}

// parseFirmlinks reads /usr/share/firmlinks, whose lines are
// "/Users<TAB>Users": a folder on the system volume, then the folder on the
// data volume that it shows. It returns the data volume's folders by their
// full path, /System/Volumes/Data/Users, with the usual path, /Users.
func parseFirmlinks(content string) map[string]string {
	firmlinks := map[string]string{}
	for _, line := range strings.Split(content, "\n") {
		part := strings.Split(line, "\t")
		if len(part) >= 2 && part[0] != "" && part[1] != "" {
			firmlinks["/System/Volumes/Data/"+part[1]] = part[0]
		}
	}
	return firmlinks
}

// usualPath turns a path on the data volume into its usual path, through the
// longest firmlink that the path is inside: /System/Volumes/Data/Users/jane
// becomes /Users/jane. Other paths are returned as they are.
func usualPath(p string, firmlinks map[string]string) string {
	best := ""
	for target := range firmlinks {
		if (p == target || strings.HasPrefix(p, target+"/")) && len(target) > len(best) {
			best = target
		}
	}
	if best == "" {
		return p
	}
	return firmlinks[best] + p[len(best):]
}

var frameworkVersion = regexp.MustCompile(`/Versions/[^/]+$`)

// isFrameworkBinary reports whether name is the binary of the framework that
// folder dir is in: Foo.framework/Foo or Foo.framework/Versions/<version>/Foo.
func isFrameworkBinary(dir, name string) bool {
	framework := frameworkVersion.ReplaceAllString(dir, "")
	return strings.HasSuffix(framework, ".framework") && filepath.Base(framework) == name+".framework"
}

// machOSignatures are the first four bytes of a Mach-O program, 32 or 64-bit
// in either byte order, and of a universal binary.
var machOSignatures = []string{
	"\xfe\xed\xfa\xce", "\xfe\xed\xfa\xcf",
	"\xce\xfa\xed\xfe", "\xcf\xfa\xed\xfe",
	"\xca\xfe\xba\xbe", "\xca\xfe\xba\xbf",
}

// isMachO tells a Mach-O program or universal binary by its first bytes.
// Java class files start like a universal binary; checkFile counts them as
// Other by their name before this is asked.
func isMachO(head []byte) bool {
	if len(head) < 4 {
		return false
	}
	for _, signature := range machOSignatures {
		if string(head[:4]) == signature {
			return true
		}
	}
	return false
}

// bundleVersion is an app's version, as list_installed_software.sh reads it
// from Info.plist: CFBundleShortVersionString, or CFBundleVersion if that
// can't be read. read returns a key's value and whether it could be read. An
// empty version becomes N/A in the list.
func bundleVersion(read func(key string) (string, bool)) string {
	if v, ok := read("CFBundleShortVersionString"); ok {
		return v
	}
	if v, ok := read("CFBundleVersion"); ok {
		return v
	}
	return ""
}

// homebrewVersions lists the Homebrew formulae and casks installed under each
// prefix as "name<TAB>version", as list_installed_software.sh does: the
// version folders in <prefix>/Cellar/<name>/ and <prefix>/Caskroom/<name>/.
// Names starting with "." (e.g. .metadata) are skipped, as the script's *
// skips them. A name found more than once is listed with its latest version.
func homebrewVersions(prefixes []string) []string {
	var lines []string
	for _, prefix := range prefixes {
		if prefix == "" {
			continue
		}
		for _, kind := range []string{"Cellar", "Caskroom"} {
			names, _ := os.ReadDir(filepath.Join(prefix, kind))
			for _, name := range names {
				if strings.HasPrefix(name.Name(), ".") {
					continue
				}
				folder := filepath.Join(prefix, kind, name.Name())
				versions, _ := os.ReadDir(folder) // fails for a file
				for _, version := range versions {
					if strings.HasPrefix(version.Name(), ".") {
						continue
					}
					// Like the script's trailing /, a link to a folder counts
					if info, err := os.Stat(filepath.Join(folder, version.Name())); err == nil && info.IsDir() {
						lines = append(lines, name.Name()+"\t"+version.Name())
					}
				}
			}
		}
	}
	return latestVersions(lines)
}

// latestVersions keeps one "name<TAB>version" line for each name, with its
// latest version by isLaterVersion, in the order the names first appear.
func latestVersions(lines []string) []string {
	latest := map[string]string{}
	var names []string
	for _, line := range lines {
		name, version, _ := strings.Cut(line, "\t")
		current, found := latest[name]
		if !found {
			names = append(names, name)
		}
		if !found || isLaterVersion(version, current) {
			latest[name] = version
		}
	}
	var out []string
	for _, name := range names {
		out = append(out, name+"\t"+latest[name])
	}
	return out
}

var versionSeparator = regexp.MustCompile(`[^0-9A-Za-z]+`)
var digits = regexp.MustCompile(`^[0-9]+$`)

// isLaterVersion reports whether version a is later than b, as
// list_installed_software.sh compares them: part by part, split at anything
// but letters and digits, comparing numbers as numbers and other parts as
// text (1.10 > 1.9, 2.0_1 > 2.0). If one runs out of parts first, the one
// with more parts is later.
func isLaterVersion(a, b string) bool {
	pa, pb := versionParts(a), versionParts(b)
	for i := 0; i < len(pa) && i < len(pb); i++ {
		x, y := pa[i], pb[i]
		if digits.MatchString(x) && digits.MatchString(y) {
			if c := compareNumbers(x, y); c != 0 {
				return c > 0
			}
			continue
		}
		if x != y {
			return x > y
		}
	}
	return len(pa) > len(pb)
}

// versionParts splits a version as awk's split does: an empty version has no
// parts.
func versionParts(v string) []string {
	if v == "" {
		return nil
	}
	return versionSeparator.Split(v, -1)
}

// compareNumbers compares two strings of digits by their value, however long
// they are: 007 equals 7.
func compareNumbers(x, y string) int {
	x, y = strings.TrimLeft(x, "0"), strings.TrimLeft(y, "0")
	if len(x) != len(y) {
		if len(x) > len(y) {
			return 1
		}
		return -1
	}
	return strings.Compare(x, y)
}
