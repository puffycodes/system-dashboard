// Command system-dashboard serves the system dashboard on http://localhost:<port>/.
//
// It is a single self-contained executable for Windows or Linux: the web UI
// in www/ is embedded at build time, so the binary can be copied to any
// machine of that OS and run with nothing installed.
//
// It listens on localhost only: the API exposes machine details and has no
// authentication. Press Ctrl+C to stop.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	port := flag.Int("port", 8080, "port to listen on")
	open := flag.Bool("open", true, "open the dashboard in the default browser on start")
	flag.Parse()

	if *port < 1 || *port > 65535 {
		fmt.Fprintf(os.Stderr, "invalid -port %d: must be 1-65535\n", *port)
		os.Exit(2)
	}

	log.SetFlags(log.Ltime)

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("Could not listen on %s. Is the port already in use? Try -port <other>. (%v)", addr, err)
	}

	srv := &http.Server{
		Handler:           newHandler(getInstalledSoftware),
		ReadHeaderTimeout: 10 * time.Second,
	}

	url := fmt.Sprintf("http://localhost:%d/", *port)
	fmt.Printf("System dashboard running at %s (Ctrl+C to stop)\n", url)
	if *open {
		openBrowser(url, *port)
	}

	// On Ctrl+C (or SIGTERM from kill/systemd), stop accepting connections and
	// let in-flight requests finish
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	stopped := make(chan struct{})
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(shutdownCtx)
		close(stopped)
	}()

	if err := srv.Serve(listener); !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
	<-stopped
	fmt.Println("Server stopped.")
}
