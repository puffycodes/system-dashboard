package main

import (
	"log"
	"os/exec"
)

// openBrowser opens the dashboard in the default browser with open.
func openBrowser(url string, port int) {
	cmd := exec.Command("/usr/bin/open", url)
	if err := cmd.Start(); err != nil {
		log.Printf("Could not open the browser: %v. Open %s manually.", err, url)
		return
	}
	go cmd.Wait()
}
