package main

import (
	"sort"
	"strconv"
	"strings"

	"golang.org/x/sys/windows/registry"
)

// The registry Uninstall keys that "Programs and Features" uses.
var uninstallKeys = []struct {
	root registry.Key
	path string
}{
	{registry.LOCAL_MACHINE, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
	{registry.LOCAL_MACHINE, `SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`},
	{registry.CURRENT_USER, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
}

// getInstalledSoftware lists installed software with the same source and
// filtering as src/useful-scripts/list_installed_software.ps1: entries without
// a DisplayName, system components, and updates/hotfixes attached to a parent
// product are skipped. See docs/spec/list_installed_software.md.
func getInstalledSoftware() []Software {
	var list []Software
	for _, key := range uninstallKeys {
		// WOW64_64KEY reads the 64-bit view even from a 32-bit build
		parent, err := registry.OpenKey(key.root, key.path, registry.ENUMERATE_SUB_KEYS|registry.WOW64_64KEY)
		if err != nil {
			continue // a missing key just has no entries
		}
		names, err := parent.ReadSubKeyNames(-1)
		parent.Close()
		if err != nil {
			continue
		}
		for _, name := range names {
			if s, ok := readEntry(key.root, key.path+`\`+name); ok {
				list = append(list, s)
			}
		}
	}
	return uniqueSorted(list)
}

func readEntry(root registry.Key, path string) (Software, bool) {
	k, err := registry.OpenKey(root, path, registry.QUERY_VALUE|registry.WOW64_64KEY)
	if err != nil {
		return Software{}, false
	}
	defer k.Close()

	name := strings.TrimSpace(valueText(k, "DisplayName"))
	if name == "" || valueText(k, "SystemComponent") == "1" || valueText(k, "ParentKeyName") != "" {
		return Software{}, false
	}
	switch strings.ToLower(valueText(k, "ReleaseType")) {
	case "update", "hotfix", "security update":
		return Software{}, false
	}

	version := strings.TrimSpace(valueText(k, "DisplayVersion"))
	if version == "" {
		version = "N/A"
	}
	return Software{Name: name, Version: version}, true
}

// valueText reads a string or integer value as text; a missing value reads as "".
func valueText(k registry.Key, name string) string {
	if s, _, err := k.GetStringValue(name); err == nil {
		return s
	}
	if n, _, err := k.GetIntegerValue(name); err == nil {
		return strconv.FormatUint(n, 10)
	}
	return ""
}

// uniqueSorted sorts by name then version, case-insensitively, and drops
// duplicates: the same app can appear in multiple hives.
func uniqueSorted(list []Software) []Software {
	sort.Slice(list, func(i, j int) bool {
		a, b := strings.ToLower(list[i].Name), strings.ToLower(list[j].Name)
		if a != b {
			return a < b
		}
		return strings.ToLower(list[i].Version) < strings.ToLower(list[j].Version)
	})
	unique := list[:0]
	for _, s := range list {
		if n := len(unique); n > 0 &&
			strings.EqualFold(unique[n-1].Name, s.Name) &&
			strings.EqualFold(unique[n-1].Version, s.Version) {
			continue
		}
		unique = append(unique, s)
	}
	return unique
}
