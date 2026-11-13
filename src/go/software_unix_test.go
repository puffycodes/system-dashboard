//go:build linux || darwin

package main

import (
	"reflect"
	"testing"
)

func TestToSoftware(t *testing.T) {
	lines := []string{"zlib\t1.3", "Firefox\t131.0", "bash\t5.2", "zlib\t1.3", "noversion\t", "\torphan-version", "extra\t1.0\tignored"}
	want := []Software{
		{"Firefox", "131.0"}, // byte order: uppercase sorts first, as with LC_ALL=C
		{"bash", "5.2"},
		{"extra", "1.0"},
		{"noversion", "N/A"},
		{"zlib", "1.3"},
	}
	if got := toSoftware(lines); !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v, want %+v", got, want)
	}
}
