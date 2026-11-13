package main

import (
	"os"
	"regexp"
	"strings"
)

// getInstalledSoftware lists installed packages with the same sources and
// output as src/useful-scripts/list_installed_software.sh: the first native
// package manager found (dpkg, rpm, pacman or apk), plus Flatpak apps and
// Snaps when present. See docs/spec/list_installed_software.md.
//
// Like the script, each source yields "name<TAB>version" lines, which are
// de-duplicated and sorted byte-wise (LC_ALL=C sort -u) before parsing.
func getInstalledSoftware() []Software {
	var lines []string

	switch {
	case has("dpkg-query"):
		lines = append(lines, parseDpkg(run("dpkg-query", "-W", "-f=${Status}\t${Package}\t${Version}\n"))...)
	case has("rpm"):
		lines = append(lines, splitLines(run("rpm", "-qa", "--qf", "%{NAME}\t%{VERSION}-%{RELEASE}\n"))...)
	case has("pacman"):
		lines = append(lines, firstTwoFields(run("pacman", "-Q"), 0)...)
	case has("apk"):
		lines = append(lines, parseApk(run("apk", "info", "-v"))...)
	}

	if has("flatpak") {
		lines = append(lines, splitLines(run("flatpak", "list", "--app", "--columns=name,version"))...)
	}

	// snap blocks when snapd isn't running (e.g. WSL without systemd)
	if info, err := os.Stat("/run/snapd.socket"); err == nil && info.Mode()&os.ModeSocket != 0 && has("snap") {
		lines = append(lines, firstTwoFields(run("snap", "list"), 1)...)
	}

	return toSoftware(lines)
}

// parseDpkg keeps fully installed packages: "<status>\t<name>\t<version>" with
// a status ending in " installed" (awk '$1 ~ / installed$/').
func parseDpkg(out string) []string {
	var lines []string
	for _, line := range splitLines(out) {
		fields := strings.Split(line, "\t")
		if len(fields) >= 3 && strings.HasSuffix(fields[0], " installed") {
			lines = append(lines, fields[1]+"\t"+fields[2])
		}
	}
	return lines
}

// firstTwoFields turns whitespace-separated "name version ..." lines into
// "name\tversion", skipping the first skip lines (awk '{ print $1 "\t" $2 }').
func firstTwoFields(out string, skip int) []string {
	var lines []string
	for i, line := range strings.Split(out, "\n") {
		if i < skip {
			continue
		}
		fields := strings.Fields(line)
		switch len(fields) {
		case 0:
		case 1:
			lines = append(lines, fields[0]+"\t")
		default:
			lines = append(lines, fields[0]+"\t"+fields[1])
		}
	}
	return lines
}

var apkPackage = regexp.MustCompile(`^(.*)-([^-]*-r[0-9]+)$`)

// parseApk splits "name-1.2.3-r0" into name and 1.2.3-r0; other lines are dropped.
func parseApk(out string) []string {
	var lines []string
	for _, line := range splitLines(out) {
		if m := apkPackage.FindStringSubmatch(line); m != nil {
			lines = append(lines, m[1]+"\t"+m[2])
		}
	}
	return lines
}
