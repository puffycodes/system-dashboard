//go:build linux || darwin

package main

import (
	"context"
	"os/exec"
	"sort"
	"strings"
	"time"
)

// The parts of getInstalledSoftware that Linux and macOS share: running
// commands, and turning "name<TAB>version" lines into the list, as the
// script's LC_ALL=C sort -u and output do.

func has(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

// run returns a command's stdout, ignoring its exit status and stderr like the
// script's 2>/dev/null. The timeout guards against a package manager hanging.
func run(name string, args ...string) string {
	out, _ := runStatus(name, args...)
	return out
}

// runStatus returns a command's stdout, and an error if it could not run or
// exited with a non-zero status, for a script's "command || fallback".
func runStatus(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).Output()
	return string(out), err
}

func splitLines(out string) []string {
	var lines []string
	for _, line := range strings.Split(out, "\n") {
		if line != "" {
			lines = append(lines, line)
		}
	}
	return lines
}

// toSoftware de-duplicates and sorts the lines byte-wise, then takes the first
// two tab-separated fields as name and version. Lines without a name are
// skipped and a missing version becomes N/A.
func toSoftware(lines []string) []Software {
	sort.Strings(lines)
	var list []Software
	for i, line := range lines {
		if i > 0 && line == lines[i-1] {
			continue
		}
		fields := strings.SplitN(line, "\t", 3)
		if fields[0] == "" {
			continue
		}
		version := "N/A"
		if len(fields) > 1 && fields[1] != "" {
			version = fields[1]
		}
		list = append(list, Software{Name: fields[0], Version: version})
	}
	return list
}
