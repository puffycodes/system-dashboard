package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppendExecutablesCategories(t *testing.T) {
	dir := t.TempDir()
	files := []struct {
		name    string
		content string
		mode    os.FileMode
	}{
		{"prog", "\x7fELF\x02\x01", 0o755},
		{"script.sh", "#!/bin/sh\n", 0o755},
		{"data.bin", "x", 0o755},
		{"empty", "", 0o755},
		{"plain.txt", "x", 0o644},
		{"libx.so.1", "x", 0o644},
		{"libexec.so", "\x7fELF", 0o755},
		{"pkg.deb", "x", 0o644},
		{"setup.run", "#!/bin/sh\n", 0o755},
	}
	for _, f := range files {
		if err := os.WriteFile(filepath.Join(dir, f.name), []byte(f.content), f.mode); err != nil {
			t.Fatal(err)
		}
	}
	os.Symlink("prog", filepath.Join(dir, "link"))

	all, _ := parseCategories("all")
	got := map[string]string{}
	for _, e := range sortExecutables(appendExecutables(nil, dir, all), strings.Compare) {
		if e.Directory != dir {
			t.Errorf("%s: directory %q, want %q", e.Name, e.Directory, dir)
		}
		got[e.Name] = e.Category
	}
	want := map[string]string{
		"prog":       "Executable",
		"script.sh":  "Script",
		"data.bin":   "Other",
		"empty":      "Other",
		"libx.so.1":  "Library",
		"libexec.so": "Library",
		"pkg.deb":    "Installer",
		"setup.run":  "Installer",
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
	onlyExe, _ := parseCategories("executable")
	list := appendExecutables(nil, dir, onlyExe)
	if len(list) != 1 || list[0].Name != "prog" {
		t.Errorf("executable only: got %+v", list)
	}
}

func TestLocalMountPoints(t *testing.T) {
	roots := localMountPoints()
	if len(roots) == 0 {
		t.Fatal("no local mount points found")
	}
	for _, root := range roots {
		if strings.HasPrefix(root, "/proc") || strings.HasPrefix(root, "/sys") {
			t.Errorf("virtual filesystem %q listed", root)
		}
	}
}

func TestUnescapeMountPath(t *testing.T) {
	if got := unescapeMountPath(`/mnt/my\040disk\134x`); got != `/mnt/my disk\x` {
		t.Errorf("got %q", got)
	}
}
