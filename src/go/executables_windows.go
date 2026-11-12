package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// extensionCategories maps file extensions to categories, as in
// src/useful-scripts/list_executables.ps1. Any other extension in PATHEXT is
// Other.
func extensionCategories() map[string]string {
	categories := map[string]string{}
	add := func(category string, exts ...string) {
		for _, ext := range exts {
			categories[ext] = category
		}
	}
	add("Executable", ".exe", ".com", ".scr")
	add("Library", ".dll", ".ocx")
	add("Script", ".bat", ".cmd", ".ps1", ".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh")
	add("Installer", ".msi", ".msp", ".msix", ".msixbundle", ".appx", ".appxbundle")

	validExt := regexp.MustCompile(`^\.\w+$`)
	for _, ext := range strings.Split(os.Getenv("PATHEXT"), ";") {
		ext = strings.ToLower(ext)
		if _, ok := categories[ext]; !ok && validExt.MatchString(ext) {
			categories[ext] = "Other"
		}
	}
	return categories
}

// findExecutables lists the files in the wanted categories on the fixed
// (local) drives, like src/useful-scripts/list_executables.ps1. Folders that
// can't be read are skipped, and junctions and symbolic links to folders are
// not followed. See docs/spec/list_executables.md.
func findExecutables(want map[string]bool) []Executable {
	wanted := map[string]string{}
	for ext, category := range extensionCategories() {
		if want[category] {
			wanted[ext] = category
		}
	}

	var list []Executable
	stack := fixedDrives()
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
			info, err := entry.Info()
			if err != nil {
				continue
			}
			attrs := uint32(0)
			if data, ok := info.Sys().(*syscall.Win32FileAttributeData); ok {
				attrs = data.FileAttributes
			}
			if attrs&windows.FILE_ATTRIBUTE_DIRECTORY != 0 {
				// Junctions and folder symlinks lead to folders searched elsewhere
				if attrs&windows.FILE_ATTRIBUTE_REPARSE_POINT == 0 {
					stack = append(stack, filepath.Join(dir, entry.Name()))
				}
				continue
			}
			category, ok := wanted[strings.ToLower(filepath.Ext(entry.Name()))]
			if !ok {
				continue
			}
			list = append(list, Executable{
				Name:      entry.Name(),
				Directory: dir,
				Size:      info.Size(),
				Modified:  modifiedTime(info.ModTime()),
				Category:  category,
			})
		}
	}
	return sortExecutables(list, compareLikeSortObject)
}

var procCompareStringEx = windows.NewLazySystemDLL("kernel32.dll").NewProc("CompareStringEx")

// compareLikeSortObject compares the way Sort-Object does in
// list_executables.ps1: with the user's locale, ignoring case. This is the
// Windows comparison .NET uses, which e.g. ignores hyphens, so
// "containerd.exe" sorts before "containerd-shim.exe".
func compareLikeSortObject(a, b string) int {
	const normIgnoreCase = 0x1
	pa, errA := windows.UTF16PtrFromString(a)
	pb, errB := windows.UTF16PtrFromString(b)
	if errA == nil && errB == nil {
		// LOCALE_NAME_USER_DEFAULT is NULL; lengths of -1 mean NUL-terminated
		r, _, _ := procCompareStringEx.Call(0, normIgnoreCase,
			uintptr(unsafe.Pointer(pa)), ^uintptr(0), uintptr(unsafe.Pointer(pb)), ^uintptr(0), 0, 0, 0)
		if r != 0 {
			return int(r) - 2 // CSTR_LESS_THAN 1, CSTR_EQUAL 2, CSTR_GREATER_THAN 3
		}
	}
	return strings.Compare(strings.ToLower(a), strings.ToLower(b))
}

// fixedDrives returns the root folder of each fixed drive, e.g. `C:\`.
func fixedDrives() []string {
	mask, err := windows.GetLogicalDrives()
	if err != nil {
		return nil
	}
	var roots []string
	for i := 0; i < 26; i++ {
		if mask&(1<<i) == 0 {
			continue
		}
		root := string(rune('A'+i)) + `:\`
		p, err := windows.UTF16PtrFromString(root)
		if err == nil && windows.GetDriveType(p) == windows.DRIVE_FIXED {
			roots = append(roots, root)
		}
	}
	return roots
}
