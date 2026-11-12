package main

import "testing"

func TestExtensionCategories(t *testing.T) {
	t.Setenv("PATHEXT", ".COM;.EXE;.BAT;.MSC;.PY;bad")
	categories := extensionCategories()
	tests := map[string]string{
		".exe": "Executable",
		".dll": "Library",
		".ps1": "Script",
		".msi": "Installer",
		".msc": "Other", // from PATHEXT
		".py":  "Other",
		".com": "Executable", // in PATHEXT, but already a program
		".bat": "Script",
		".txt": "",
		"bad":  "",
	}
	for ext, want := range tests {
		if got := categories[ext]; got != want {
			t.Errorf("%s: category %q, want %q", ext, got, want)
		}
	}
}

func TestFixedDrives(t *testing.T) {
	if len(fixedDrives()) == 0 {
		t.Error("no fixed drives found")
	}
}

func TestCompareLikeSortObject(t *testing.T) {
	if c := compareLikeSortObject("Setup.EXE", "setup.exe"); c != 0 {
		t.Errorf("case: got %d, want 0", c)
	}
	// As in Sort-Object, hyphens are ignored
	if c := compareLikeSortObject("containerd.exe", "containerd-shim-crx-v2.exe"); c >= 0 {
		t.Errorf("containerd.exe vs containerd-shim-crx-v2.exe: got %d, want < 0", c)
	}
	if c := compareLikeSortObject("b", "a"); c <= 0 {
		t.Errorf("b vs a: got %d, want > 0", c)
	}
}
