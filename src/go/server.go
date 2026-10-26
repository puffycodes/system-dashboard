package main

import (
	"embed"
	"encoding/json"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path"
	"time"
)

//go:embed www
var wwwFiles embed.FS

// Software is one installed program, serialised as { "Name": ..., "Version": ... }.
// Each OS provides getInstalledSoftware in software_<os>.go.
type Software struct {
	Name    string `json:"Name"`
	Version string `json:"Version"`
}

// Set explicitly: on Windows, Go's mime package takes types from the registry,
// which some machines map wrongly (e.g. .js as text/plain).
var contentTypes = map[string]string{
	".html": "text/html; charset=utf-8",
	".css":  "text/css; charset=utf-8",
	".js":   "text/javascript; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".svg":  "image/svg+xml",
	".png":  "image/png",
	".ico":  "image/x-icon",
}

// newHandler builds the dashboard's routes:
//
//	GET /               -> www/index.html
//	GET /<file>         -> static file from www/
//	GET /api/software   -> { computerName, generatedAt, items: [{ Name, Version }] }
func newHandler(listSoftware func() []Software) http.Handler {
	www, err := fs.Sub(wwwFiles, "www")
	if err != nil {
		panic(err)
	}
	static := http.FileServer(http.FS(www))

	mux := http.NewServeMux()
	mux.HandleFunc("/api/software", func(w http.ResponseWriter, r *http.Request) {
		items := listSoftware()
		if items == nil {
			items = []Software{}
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"computerName": computerName(),
			"generatedAt":  time.Now().Format(time.RFC3339Nano),
			"items":        items,
		})
	})
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Unknown endpoint: " + r.URL.Path})
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if ct, ok := contentTypes[path.Ext(r.URL.Path)]; ok {
			w.Header().Set("Content-Type", ct)
		}
		static.ServeHTTP(w, r)
	})

	return logRequests(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		mux.ServeHTTP(w, r)
	}))
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// computerName matches $env:COMPUTERNAME in the PowerShell version on Windows,
// and uname -n in list_installed_software.sh on Linux.
func computerName() string {
	if name := os.Getenv("COMPUTERNAME"); name != "" {
		return name
	}
	name, _ := os.Hostname()
	return name
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(status int) {
	s.status = status
	s.ResponseWriter.WriteHeader(status)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s %d", r.Method, r.URL.Path, rec.status)
	})
}
