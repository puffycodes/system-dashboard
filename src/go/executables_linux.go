package main

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
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

// appendExecutables searches the folder tree at root without crossing into
// other filesystems, like find -xdev. A root that is a file (a bind-mounted
// file) is checked on its own, as find does.
func appendExecutables(list []Executable, root string, want map[string]bool) []Executable {
	rootInfo, err := os.Lstat(root)
	if err != nil {
		return list
	}
	if rootInfo.Mode().IsRegular() {
		if e, ok := checkFile(filepath.Dir(root), rootInfo, want); ok {
			list = append(list, e)
		}
		return list
	}
	if !rootInfo.IsDir() {
		return list
	}
	rootDev := rootInfo.Sys().(*syscall.Stat_t).Dev

	stack := []string{root}
	for len(stack) > 0 {
		dir := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		f, err := os.Open(dir)
		if err != nil {
			continue
		}
		entries, _ := f.ReadDir(-1) // keeps what was read before an error
		f.Close()

		for _, entry := range entries {
			if entry.IsDir() {
				if info, err := entry.Info(); err == nil && info.Sys().(*syscall.Stat_t).Dev == rootDev {
					stack = append(stack, filepath.Join(dir, entry.Name()))
				}
				continue
			}
			if !entry.Type().IsRegular() { // symbolic links and special files
				continue
			}
			info, err := entry.Info()
			if err != nil {
				continue
			}
			if e, ok := checkFile(dir, info, want); ok {
				list = append(list, e)
			}
		}
	}
	return list
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
		category = contentCategory(filepath.Join(dir, name))
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

// contentCategory tells a program from a script by its first bytes: an ELF
// program starts with "\x7fELF" and a script with "#!". A file that can't be
// read is most likely a program.
func contentCategory(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return "Executable"
	}
	defer f.Close()
	head := make([]byte, 4)
	n, err := io.ReadFull(f, head)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return "Executable"
	}
	head = head[:n]
	switch {
	case strings.HasPrefix(string(head), "\x7fELF"):
		return "Executable"
	case strings.HasPrefix(string(head), "#!"):
		return "Script"
	}
	return "Other"
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
