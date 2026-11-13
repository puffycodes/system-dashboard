package main

import (
	"reflect"
	"testing"
)

func TestParseDpkg(t *testing.T) {
	out := "install ok installed\tbash\t5.2.21-2ubuntu4\n" +
		"deinstall ok config-files\told-pkg\t1.0\n" +
		"install ok installed\tlibc6\t2.39-0ubuntu8\n"
	want := []string{"bash\t5.2.21-2ubuntu4", "libc6\t2.39-0ubuntu8"}
	if got := parseDpkg(out); !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestFirstTwoFields(t *testing.T) {
	// snap list: header row, then whitespace-aligned columns
	out := "Name    Version   Rev\ncore22  20240111  1122\nlonely\n\n"
	want := []string{"core22\t20240111", "lonely\t"}
	if got := firstTwoFields(out, 1); !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestParseApk(t *testing.T) {
	out := "musl-1.2.4-r2\nca-certificates-bundle-20230506-r0\nWARNING: not a package\n"
	want := []string{"musl\t1.2.4-r2", "ca-certificates-bundle\t20230506-r0"}
	if got := parseApk(out); !reflect.DeepEqual(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestGetInstalledSoftware(t *testing.T) {
	list := getInstalledSoftware()
	if len(list) == 0 {
		t.Skip("no supported package manager found on this machine")
	}
	for i, s := range list {
		if s.Name == "" || s.Version == "" {
			t.Errorf("entry %d has an empty field: %+v", i, s)
		}
	}
}
