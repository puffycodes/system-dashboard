package main

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"
)

// The tests of macos.go, which run on any machine.

func TestParseMacMounts(t *testing.T) {
	out := "/dev/disk3s1s1 on / (apfs, sealed, local, read-only, journaled)\n" +
		"devfs on /dev (devfs, local, nobrowse)\n" +
		"/dev/disk3s6 on /System/Volumes/VM (apfs, local, noexec, journaled, noatime, nobrowse)\n" +
		"/dev/disk3s2 on /System/Volumes/Preboot (apfs, local, journaled, nobrowse)\n" +
		"/dev/disk3s4 on /System/Volumes/Update (apfs, local, journaled, nobrowse)\n" +
		"/dev/disk1s2 on /System/Volumes/xarts (apfs, local, noexec, journaled, noatime, nobrowse)\n" +
		"/dev/disk1s1 on /System/Volumes/iSCPreboot (apfs, local, journaled, nobrowse)\n" +
		"/dev/disk1s3 on /System/Volumes/Hardware (apfs, local, journaled, nobrowse)\n" +
		"/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse, protect)\n" +
		"map auto_home on /System/Volumes/Data/home (autofs, automounted, nobrowse)\n" +
		"/dev/disk3s5 on /System/Volumes/Data/private/x (apfs, local, journaled, nobrowse)\n" +
		"/dev/disk5s1 on /Volumes/My Disk (on USB) (apfs, local, nodev, nosuid, journaled, noowners)\n" +
		"/dev/disk6s1 on /Volumes/Installer Image (hfs, local, nodev, nosuid, read-only, noowners, quarantine, mounted by jane)\n" +
		"//jane@nas/share on /Volumes/share (smbfs, nodev, nosuid, mounted by jane)\n" +
		"com.apple.TimeMachine.2026-11-12-101500.local@/dev/disk3s5 on /Volumes/com.apple.TimeMachine.localsnapshots/Backups.backupdb/x (apfs, local, read-only, journaled, nobrowse)\n" +
		"/dev/disk7s1 on /Volumes/.timemachine/ABC/2026-11-12-101500.backup (apfs, local, nodev, nosuid, read-only, journaled, nobrowse)\n" +
		"not a mount line\n"
	want := []string{"/", "/System/Volumes/Data", "/Volumes/My Disk (on USB)", "/Volumes/Installer Image"}
	if got := parseMacMounts(out); !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestUsualPath(t *testing.T) {
	firmlinks := parseFirmlinks("/Users\tUsers\n/Applications\tApplications\n/usr/local\tusr/local\n/Library\tLibrary\n\nbad line\n")
	if len(firmlinks) != 4 || firmlinks["/System/Volumes/Data/usr/local"] != "/usr/local" {
		t.Fatalf("firmlinks: %v", firmlinks)
	}
	for p, want := range map[string]string{
		"/System/Volumes/Data/Users/jane/bin":     "/Users/jane/bin",
		"/System/Volumes/Data/Users":              "/Users",
		"/System/Volumes/Data/usr/local/bin":      "/usr/local/bin",
		"/System/Volumes/Data/UsersX/bin":         "/System/Volumes/Data/UsersX/bin", // not inside /Users
		"/System/Volumes/Data/sw/bin":             "/System/Volumes/Data/sw/bin",
		"/usr/bin":                                "/usr/bin",
		"/System/Volumes/Data/Library/Frameworks": "/Library/Frameworks",
	} {
		if got := usualPath(p, firmlinks); got != want {
			t.Errorf("%s: got %s, want %s", p, got, want)
		}
	}
	// The longest firmlink wins
	nested := map[string]string{"/System/Volumes/Data/a": "/a", "/System/Volumes/Data/a/b": "/b"}
	if got := usualPath("/System/Volumes/Data/a/b/c", nested); got != "/b/c" {
		t.Errorf("nested: got %s", got)
	}
}

func TestIsFrameworkBinary(t *testing.T) {
	for _, c := range []struct {
		dir, name string
		want      bool
	}{
		{"/Library/Frameworks/Foo.framework/Versions/A", "Foo", true},
		{"/Library/Frameworks/Foo.framework/Versions/Current", "Foo", true},
		{"/Applications/X.app/Contents/Frameworks/Bar.framework", "Bar", true},
		{"/Applications/X.app/Contents/Frameworks/Bar.framework", "NotBar", false},
		{"/Library/Frameworks/Foo.framework/Versions/A/Resources", "Foo", false},
		{"/Library/Frameworks/Foo.framework/Versions", "Foo", false},
		{"/usr/lib", "Foo", false},
	} {
		if got := isFrameworkBinary(c.dir, c.name); got != c.want {
			t.Errorf("%s/%s: got %v, want %v", c.dir, c.name, got, c.want)
		}
	}
}

func TestIsMachO(t *testing.T) {
	for head, want := range map[string]bool{
		"\xcf\xfa\xed\xfe\x0c\x00": true, // 64-bit, little-endian (arm64, x86-64)
		"\xce\xfa\xed\xfe":         true, // 32-bit
		"\xfe\xed\xfa\xcf":         true, // big-endian
		"\xfe\xed\xfa\xce":         true,
		"\xca\xfe\xba\xbe\x00\x00": true, // universal
		"\xca\xfe\xba\xbf":         true, // universal, 64-bit
		"\x7fELF":                  false,
		"#!/bin/sh":                false,
		"\xcf\xfa\xed":             false, // too short
		"":                         false,
	} {
		if got := isMachO([]byte(head)); got != want {
			t.Errorf("%q: got %v, want %v", head, got, want)
		}
	}
}

func TestBundleVersion(t *testing.T) {
	plist := func(values map[string]string) func(string) (string, bool) {
		return func(key string) (string, bool) { v, ok := values[key]; return v, ok }
	}
	for _, c := range []struct {
		values map[string]string
		want   string
	}{
		{map[string]string{"CFBundleShortVersionString": "131.0.6778.86", "CFBundleVersion": "6778.86"}, "131.0.6778.86"},
		{map[string]string{"CFBundleVersion": "42"}, "42"},
		{map[string]string{}, ""},
	} {
		if got := bundleVersion(plist(c.values)); got != c.want {
			t.Errorf("%v: got %q, want %q", c.values, got, c.want)
		}
	}
}

func TestIsLaterVersion(t *testing.T) {
	for _, c := range []struct {
		a, b string
		want bool
	}{
		{"2.47.0", "2.9.1", true}, // numbers as numbers
		{"2.9.1", "2.47.0", false},
		{"1.10", "1.9", true},
		{"3.12.7_1", "3.12.7", true}, // more parts
		{"3.12.7", "3.12.7_1", false},
		{"1.0", "1.0", false},
		{"1.007", "1.7", false}, // equal numbers
		{"1.7", "1.007", false},
		{"1.0b", "1.0a", true}, // text as text
		{"latest", "1.0", true},
		{"2", "", true},
		{"123456789012345678901", "99999999999999999999", true}, // longer than int64
	} {
		if got := isLaterVersion(c.a, c.b); got != c.want {
			t.Errorf("isLaterVersion(%q, %q) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

func TestHomebrewVersions(t *testing.T) {
	arm, intel := t.TempDir(), t.TempDir()
	for _, dir := range []string{
		arm + "/Cellar/git/2.47.0", arm + "/Cellar/git/2.9.1",
		arm + "/Cellar/python@3.12/3.12.7_1", arm + "/Cellar/python@3.12/3.12.7",
		arm + "/Cellar/openssl@3/3.4.0", arm + "/Cellar/empty",
		arm + "/Caskroom/visual-studio-code/1.95.3", arm + "/Caskroom/.metadata/x",
		arm + "/Caskroom/some-cask/latest", arm + "/Caskroom/some-cask/.hidden",
		intel + "/Cellar/wget/1.24.5", intel + "/Cellar/git/2.40.0",
	} {
		if err := os.MkdirAll(filepath.FromSlash(dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// Files are not versions, and a file is not a formula
	os.WriteFile(filepath.Join(arm, "Cellar", "git", "INSTALL_RECEIPT.json"), nil, 0o644)
	os.WriteFile(filepath.Join(arm, "Cellar", "notes.txt"), nil, 0o644)

	// An empty prefix (no HOMEBREW_PREFIX) and a missing one are skipped; the
	// same prefix twice lists each name once
	got := homebrewVersions([]string{"", arm, filepath.Join(arm, "missing"), intel, arm})
	sort.Strings(got)
	want := []string{
		"git\t2.47.0",
		"openssl@3\t3.4.0",
		"python@3.12\t3.12.7_1",
		"some-cask\tlatest",
		"visual-studio-code\t1.95.3",
		"wget\t1.24.5",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}
