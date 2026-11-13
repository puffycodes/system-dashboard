package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppendExecutablesCategories(t *testing.T) {
	dir := t.TempDir()
	machO := "\xcf\xfa\xed\xfe\x0c\x00\x00\x01"
	files := []struct {
		name    string
		content string
		mode    os.FileMode
	}{
		{"prog", machO, 0o755},
		{"universal", "\xca\xfe\xba\xbe\x00\x00\x00\x02", 0o755},
		{"Main.class", "\xca\xfe\xba\xbe\x00\x00\x00\x41", 0o755},
		{"elf", "\x7fELF", 0o755},
		{"script.sh", "#!/bin/sh\n", 0o755},
		{"data.bin", "x", 0o755},
		{"plain.txt", "x", 0o644},
		{"libz.dylib", "x", 0o644},
		{"mod.so", "x", 0o644},
		{"old.so.1", "x", 0o644},
		{"Setup.pkg", "x", 0o644},
		{"Meta.mpkg", "x", 0o644},
		{"App.dmg", "x", 0o644},
		{"linux.deb", "x", 0o644},
		{"Foo.framework/Versions/A/Foo", machO, 0o755},
		{"Foo.framework/Versions/A/Resources/helper", "#!/bin/sh\n", 0o755},
		{"Bar.framework/Bar", machO, 0o755},
		{"Bar.framework/NotBar", machO, 0o755},
		{"Baz.framework/Baz", machO, 0o644}, // no execute bit
	}
	for _, f := range files {
		path := filepath.Join(dir, f.name)
		os.MkdirAll(filepath.Dir(path), 0o755)
		if err := os.WriteFile(path, []byte(f.content), f.mode); err != nil {
			t.Fatal(err)
		}
	}
	os.Symlink("prog", filepath.Join(dir, "link"))

	all, _ := parseCategories("all")
	got := map[string]string{}
	for _, e := range sortExecutables(appendExecutables(nil, dir, all), strings.Compare) {
		rel, _ := filepath.Rel(dir, filepath.Join(e.Directory, e.Name))
		got[rel] = e.Category
	}
	want := map[string]string{
		"prog":                         "Executable",
		"universal":                    "Executable",
		"Main.class":                   "Other",
		"elf":                          "Other",
		"script.sh":                    "Script",
		"data.bin":                     "Other",
		"libz.dylib":                   "Library",
		"mod.so":                       "Library",
		"Setup.pkg":                    "Installer",
		"Meta.mpkg":                    "Installer",
		"App.dmg":                      "Installer",
		"Foo.framework/Versions/A/Foo": "Library",
		"Foo.framework/Versions/A/Resources/helper": "Script",
		"Bar.framework/Bar":                         "Library",
		"Bar.framework/NotBar":                      "Executable",
	}
	if len(got) != len(want) {
		t.Errorf("got %v, want %v", got, want)
	}
	for name, category := range want {
		if got[name] != category {
			t.Errorf("%s: category %q, want %q", name, got[name], category)
		}
	}

	// Only the wanted categories are listed
	onlyLib, _ := parseCategories("library")
	if list := appendExecutables(nil, dir, onlyLib); len(list) != 4 {
		t.Errorf("library only: got %+v", list)
	}
}

func TestFindExecutablesVolumes(t *testing.T) {
	roots := parseMacMounts(run("/sbin/mount"))
	if len(roots) == 0 || roots[0] != "/" {
		t.Fatalf("local volumes: got %q, want / first", roots)
	}
	for _, root := range roots {
		if macSupportVolume.MatchString(root) {
			t.Errorf("support volume %q listed", root)
		}
	}
}
