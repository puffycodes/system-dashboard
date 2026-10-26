package main

import (
	"log"
	"os/exec"
)

func openBrowser(url string, port int) {
	if err := exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start(); err != nil {
		log.Printf("Could not open the browser: %v. Open %s manually.", err, url)
	}
}
