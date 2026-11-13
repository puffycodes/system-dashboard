package main

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// virtualFilesystems are never searched, as in list_executables.sh.
var virtualFilesystems = regexp.MustCompile(`^(proc|sysfs|devtmpfs|devpts|tmpfs|ramfs|cgroup2?|securityfs|debugfs|tracefs|pstore|bpf|mqueue|hugetlbfs|configfs|fusectl|autofs|binfmt_misc|rpc_pipefs|nsfs|efivarfs|selinuxfs)$`)

// findExecutables lists the files in the wanted categories on the local
// disks, like src/useful-scripts/list_executables.sh with -c: the same
// filesystems, the same categories and the same byte-wise order. Folders that
// can't be read are skipped. See docs/spec/list_executables.md.
func findExecutables(want map[string]bool) []Executable {
	var list []Executable
	for _, root := range localMountPoints() {
		list = appendExecutables(list, root, want)
	}
	return sortExecutables(list, strings.Compare) // byte-wise, like LC_ALL=C sort
}

// checkFile returns the regular file info in folder dir as an Executable if
// it is in a wanted category. Libraries and installers are told by name,
// whatever their permissions; other files need an execute bit.
func checkFile(dir string, info os.FileInfo, want map[string]bool) (Executable, bool) {
	name := info.Name()
	var category string
	switch {
	case strings.HasSuffix(name, ".so") || strings.Contains(name, ".so."):
		category = "Library"
	case strings.HasSuffix(name, ".deb") || strings.HasSuffix(name, ".rpm") || strings.HasSuffix(name, ".run"):
		category = "Installer"
	case info.Mode().Perm()&0o111 == 0:
		return Executable{}, false
	case !want["Executable"] && !want["Script"] && !want["Other"]:
		return Executable{}, false // no need to read the file
	default:
		category = contentCategory(filepath.Join(dir, name), isELF)
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

// isELF tells an ELF program by its first bytes, "\x7fELF".
func isELF(head []byte) bool {
	return strings.HasPrefix(string(head), "\x7fELF")
}

// localMountPoints lists the mount points of the local disks from
// /proc/self/mountinfo, as list_executables.sh does: filesystems on a /dev/
// block device, plus ZFS. A filesystem mounted more than once is listed once.
func localMountPoints() []string {
	f, err := os.Open("/proc/self/mountinfo")
	if err != nil {
		return []string{"/"}
	}
	defer f.Close()

	seen := map[string]bool{}
	var roots []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		// Optional fields end with "-", then filesystem type and source
		i := 6
		for i < len(fields) && fields[i] != "-" {
			i++
		}
		if i+2 >= len(fields) {
			continue
		}
		fstype, source := fields[i+1], fields[i+2]
		if virtualFilesystems.MatchString(fstype) || (!strings.HasPrefix(source, "/dev/") && fstype != "zfs") {
			continue
		}
		key := fields[2] + " " + fields[3] // device and the folder of it that is mounted
		if !seen[key] {
			seen[key] = true
			roots = append(roots, unescapeMountPath(fields[4]))
		}
	}
	return roots
}

// unescapeMountPath undoes mountinfo's octal escapes for space, tab, newline
// and backslash.
func unescapeMountPath(s string) string {
	return strings.NewReplacer(`\040`, " ", `\011`, "\t", `\012`, "\n", `\134`, `\`).Replace(s)
}
