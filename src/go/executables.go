package main

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// Executable is one file of the executables list, with the same fields as
// list_executables. Each OS provides findExecutables in executables_<os>.go.
type Executable struct {
	Name      string `json:"Name"`
	Directory string `json:"Directory"`
	Size      int64  `json:"Size"`
	Modified  string `json:"Modified"`
	Category  string `json:"Category"`
}

// executableCategories pairs list_executables' -c names, which the API's
// categories parameter also takes, with the Category values, in list order.
var executableCategories = []struct{ param, name string }{
	{"executable", "Executable"},
	{"library", "Library"},
	{"script", "Script"},
	{"installer", "Installer"},
	{"other", "Other"},
}

// parseCategories turns a comma-separated list such as "executable,library"
// into a set of Category values, as list_executables -c does. "all" selects
// every category.
func parseCategories(s string) (map[string]bool, error) {
	want := map[string]bool{}
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		found := false
		for _, c := range executableCategories {
			if part == c.param || part == "all" {
				want[c.name] = true
				found = true
			}
		}
		if !found {
			return nil, fmt.Errorf("invalid category: %s", part)
		}
	}
	if len(want) == 0 {
		return nil, fmt.Errorf("no category given")
	}
	return want, nil
}

// categoryNames lists the categories in want, in list order.
func categoryNames(want map[string]bool) []string {
	names := []string{}
	for _, c := range executableCategories {
		if want[c.name] {
			names = append(names, c.name)
		}
	}
	return names
}

// modifiedTime formats a file's last modified time as list_executables does:
// ISO 8601 in local time with its time-zone offset, to the second.
func modifiedTime(t time.Time) string {
	return t.Local().Format("2006-01-02T15:04:05-07:00")
}

// sortExecutables sorts by directory, then name, with compare (which returns
// <0, 0 or >0, like strings.Compare), and drops a file found twice: one
// whose directory and name both compare equal.
func sortExecutables(list []Executable, compare func(a, b string) int) []Executable {
	cmp := func(a, b Executable) int {
		if c := compare(a.Directory, b.Directory); c != 0 {
			return c
		}
		return compare(a.Name, b.Name)
	}
	sort.SliceStable(list, func(i, j int) bool { return cmp(list[i], list[j]) < 0 })
	unique := list[:0]
	for _, e := range list {
		if n := len(unique); n > 0 && cmp(unique[n-1], e) == 0 {
			continue
		}
		unique = append(unique, e)
	}
	return unique
}
