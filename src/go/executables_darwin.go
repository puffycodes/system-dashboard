package main

import (
	"os"
	"path/filepath"
	"strings"
)

// findExecutables lists the files in the wanted categories on the local
// volumes, like src/useful-scripts/list_executables.sh with -c on macOS: the
// same volumes, the same categories and the same byte-wise order. Files on
// the data volume are shown under their usual paths (/Users/..., not
// /System/Volumes/Data/Users/...). Folders that can't be read are skipped.
// See docs/spec/macos.md.
func findExecutables(want map[string]bool) []Executable {
	firmlinks := map[string]string{}
	if content, err := os.ReadFile("/usr/share/firmlinks"); err == nil {
		firmlinks = parseFirmlinks(string(content))
	}
	var list []Executable
	for _, root := range parseMacMounts(run("/sbin/mount")) {
		list = appendExecutables(list, root, want)
	}
	for i := range list {
		list[i].Directory = usualPath(list[i].Directory, firmlinks)
	}
	return sortExecutables(list, strings.Compare) // byte-wise, like LC_ALL=C sort
}

// checkFile returns the regular file info in folder dir as an Executable if
// it is in a wanted category. Libraries named *.dylib or *.so and installers
// are told by name, whatever their permissions; a framework's binary and other
// files need an execute bit.
func checkFile(dir string, info os.FileInfo, want map[string]bool) (Executable, bool) {
	name := info.Name()
	executable := info.Mode().Perm()&0o111 != 0
	var category string
	switch {
	case strings.HasSuffix(name, ".dylib") || strings.HasSuffix(name, ".so"):
		category = "Library"
	case executable && isFrameworkBinary(dir, name):
		category = "Library"
	case strings.HasSuffix(name, ".pkg") || strings.HasSuffix(name, ".mpkg") || strings.HasSuffix(name, ".dmg"):
		category = "Installer"
	case !executable:
		return Executable{}, false
	case strings.HasSuffix(name, ".class"):
		category = "Other" // Java class files start like a universal binary
	case !want["Executable"] && !want["Script"] && !want["Other"]:
		return Executable{}, false // no need to read the file
	default:
		category = contentCategory(filepath.Join(dir, name), isMachO)
	}
	if !want[category] {
		return Executable{}, false
	}
	return Executable{
		Name:      name,
		Directory: dir,
		Size:      info.Size(),
		Modified:  modifiedTime(info.ModTime()),
		Category:  category,
	}, true
}
