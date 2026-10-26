package main

import (
	"fmt"
	"os"
	"os/exec"
)

// openBrowser uses xdg-open when there is a graphical session. Most Linux
// machines this runs on are headless, so otherwise it explains how to view the
// dashboard from another machine over SSH.
func openBrowser(url string, port int) {
	graphical := os.Getenv("DISPLAY") != "" || os.Getenv("WAYLAND_DISPLAY") != ""
	if graphical {
		if xdgOpen, err := exec.LookPath("xdg-open"); err == nil {
			cmd := exec.Command(xdgOpen, url) // output is discarded, keeping the request log readable
			if cmd.Start() == nil {
				go cmd.Wait()
				return
			}
		}
	}
	fmt.Printf("No browser opened. To view it from another machine, run there:\n"+
		"  ssh -L %d:localhost:%d <user>@<this-host>\n"+
		"then open %s\n", port, port, url)
}
