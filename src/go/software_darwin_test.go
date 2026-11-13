package main

import "testing"

func TestGetInstalledSoftware(t *testing.T) {
	list := getInstalledSoftware()
	if len(list) == 0 {
		t.Skip("no apps or Homebrew packages found on this machine")
	}
	for i, s := range list {
		if s.Name == "" || s.Version == "" {
			t.Errorf("entry %d has an empty field: %+v", i, s)
		}
		if s.Name == "Safari" {
			t.Errorf("Safari comes with macOS and should not be listed")
		}
	}
}
