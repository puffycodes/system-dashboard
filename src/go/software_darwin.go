package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// getInstalledSoftware lists installed software with the same sources and
// output as src/useful-scripts/list_installed_software.sh on macOS: the .app
// bundles in /Applications and ~/Applications, except the apps that come with
// macOS, plus the Homebrew formulae and casks. See docs/spec/macos.md.
func getInstalledSoftware() []Software {
	lines := macApps()
	// Apple silicon uses /opt/homebrew and Intel /usr/local; a Mac can have both
	lines = append(lines, homebrewVersions([]string{os.Getenv("HOMEBREW_PREFIX"), "/opt/homebrew", "/usr/local"})...)
	return toSoftware(lines)
}

// macApps lists "name<TAB>version" for each .app bundle in /Applications and
// ~/Applications, and in their subfolders, but not for apps inside other apps.
// The apps that come with macOS are on the read-only system volume, so an app
// on the same volume as /System/Applications is skipped.
func macApps() []string {
	systemDevice, haveSystem := device("/System/Applications")
	var lines []string
	for _, dir := range []string{"/Applications", filepath.Join(os.Getenv("HOME"), "Applications")} {
		if dir == "Applications" { // no HOME
			continue
		}
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			continue
		}
		filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return nil // a folder that can't be read is skipped
			}
			if !entry.IsDir() || !strings.HasSuffix(entry.Name(), ".app") {
				return nil
			}
			if d, ok := device(path); ok && !(haveSystem && d == systemDevice) {
				lines = append(lines, strings.TrimSuffix(entry.Name(), ".app")+"\t"+appVersion(path))
			}
			return filepath.SkipDir // not the apps inside it
		})
	}
	return lines
}

// device returns the number of the volume that path is on, without following
// a symbolic link, like stat -f %d.
func device(path string) (uint64, bool) {
	info, err := os.Lstat(path)
	if err != nil {
		return 0, false
	}
	return uint64(info.Sys().(*syscall.Stat_t).Dev), true
}

// appVersion reads an app's version from its Info.plist with plutil, which
// reads both the XML and the binary format.
func appVersion(app string) string {
	plist := filepath.Join(app, "Contents", "Info.plist")
	return bundleVersion(func(key string) (string, bool) {
		out, err := runStatus("/usr/bin/plutil", "-extract", key, "raw", "-o", "-", plist)
		return strings.TrimRight(out, "\n"), err == nil
	})
}
