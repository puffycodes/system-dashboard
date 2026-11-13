//go:build linux || darwin

package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// The parts of findExecutables that Linux and macOS share: searching a
// filesystem like find -xdev, and reading a file's first bytes. Each OS
// provides checkFile, which sorts a file into its category.

// appendExecutables searches the folder tree at root without crossing into
// other filesystems, like find -xdev. A root that is a file (a bind-mounted
// file) is checked on its own, as find does.
func appendExecutables(list []Executable, root string, want map[string]bool) []Executable {
	rootInfo, err := os.Lstat(root)
	if err != nil {
		return list
	}
	if rootInfo.Mode().IsRegular() {
		if e, ok := checkFile(filepath.Dir(root), rootInfo, want); ok {
			list = append(list, e)
		}
		return list
	}
	if !rootInfo.IsDir() {
		return list
	}
	rootDev := rootInfo.Sys().(*syscall.Stat_t).Dev

	stack := []string{root}
	for len(stack) > 0 {
		dir := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		f, err := os.Open(dir)
		if err != nil {
			continue
		}
		entries, _ := f.ReadDir(-1) // keeps what was read before an error
		f.Close()

		for _, entry := range entries {
			if entry.IsDir() {
				if info, err := entry.Info(); err == nil && info.Sys().(*syscall.Stat_t).Dev == rootDev {
					stack = append(stack, filepath.Join(dir, entry.Name()))
				}
				continue
			}
			if !entry.Type().IsRegular() { // symbolic links and special files
				continue
			}
			info, err := entry.Info()
			if err != nil {
				continue
			}
			if e, ok := checkFile(dir, info, want); ok {
				list = append(list, e)
			}
		}
	}
	return list
}

// contentCategory tells a program from a script by its first bytes: a
// program is a file that isProgram accepts (an ELF or Mach-O signature) and a
// script starts with "#!". A file that can't be read is most likely a program.
func contentCategory(path string, isProgram func(head []byte) bool) string {
	f, err := os.Open(path)
	if err != nil {
		return "Executable"
	}
	defer f.Close()
	head := make([]byte, 4)
	n, err := io.ReadFull(f, head)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return "Executable"
	}
	head = head[:n]
	switch {
	case isProgram(head):
		return "Executable"
	case strings.HasPrefix(string(head), "#!"):
		return "Script"
	}
	return "Other"
}
