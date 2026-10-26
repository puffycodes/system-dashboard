package main

import (
	"strings"
	"testing"
)

func TestGetInstalledSoftware(t *testing.T) {
	list := getInstalledSoftware()
	if len(list) == 0 {
		t.Skip("no installed software found on this machine")
	}
	for i, s := range list {
		if s.Name == "" || s.Version == "" {
			t.Errorf("entry %d has an empty field: %+v", i, s)
		}
		if i > 0 && strings.EqualFold(list[i-1].Name, s.Name) && strings.EqualFold(list[i-1].Version, s.Version) {
			t.Errorf("duplicate entry: %+v", s)
		}
	}
}

func TestUniqueSorted(t *testing.T) {
	got := uniqueSorted([]Software{
		{"beta", "2"},
		{"Alpha", "1"},
		{"alpha", "1"},
		{"Alpha", "2"},
	})
	want := []Software{{"Alpha", "1"}, {"Alpha", "2"}, {"beta", "2"}}
	if len(got) != len(want) {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	for i := range want {
		if !strings.EqualFold(got[i].Name, want[i].Name) || got[i].Version != want[i].Version {
			t.Errorf("got[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
}
