package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func stubSoftware() []Software {
	return []Software{{Name: "Example App", Version: "1.2.3"}}
}

func serve(t *testing.T, method, target string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	newHandler(stubSoftware).ServeHTTP(rec, httptest.NewRequest(method, target, nil))
	return rec
}

func TestStaticFiles(t *testing.T) {
	tests := []struct {
		path, contentType, contains string
	}{
		{"/", "text/html; charset=utf-8", "<title>System Dashboard</title>"},
		{"/app.js", "text/javascript; charset=utf-8", "loadSoftware"},
		{"/style.css", "text/css; charset=utf-8", ":root"},
	}
	for _, tt := range tests {
		rec := serve(t, http.MethodGet, tt.path)
		if rec.Code != http.StatusOK {
			t.Errorf("GET %s: status %d, want 200", tt.path, rec.Code)
			continue
		}
		if got := rec.Header().Get("Content-Type"); got != tt.contentType {
			t.Errorf("GET %s: Content-Type %q, want %q", tt.path, got, tt.contentType)
		}
		if !strings.Contains(rec.Body.String(), tt.contains) {
			t.Errorf("GET %s: body does not contain %q", tt.path, tt.contains)
		}
	}
}

func TestSoftwareAPI(t *testing.T) {
	rec := serve(t, http.MethodGet, "/api/software")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200", rec.Code)
	}
	var body struct {
		ComputerName string     `json:"computerName"`
		GeneratedAt  string     `json:"generatedAt"`
		Items        []Software `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if body.GeneratedAt == "" {
		t.Error("generatedAt is empty")
	}
	if len(body.Items) != 1 || body.Items[0] != stubSoftware()[0] {
		t.Errorf("items = %+v, want %+v", body.Items, stubSoftware())
	}
}

func TestEmptySoftwareListIsArray(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler(func() []Software { return nil }).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/software", nil))
	if !strings.Contains(rec.Body.String(), `"items":[]`) {
		t.Errorf("body = %s, want items to be []", rec.Body.String())
	}
}

func TestErrors(t *testing.T) {
	tests := []struct {
		method, path string
		status       int
	}{
		{http.MethodGet, "/nope.txt", http.StatusNotFound},
		{http.MethodGet, "/api/nope", http.StatusNotFound},
		{http.MethodGet, "/go.mod", http.StatusNotFound}, // only www/ is embedded
		{http.MethodPost, "/api/software", http.StatusMethodNotAllowed},
	}
	for _, tt := range tests {
		if rec := serve(t, tt.method, tt.path); rec.Code != tt.status {
			t.Errorf("%s %s: status %d, want %d", tt.method, tt.path, rec.Code, tt.status)
		}
	}
}

func TestTraversalIsRedirectedToCleanPath(t *testing.T) {
	rec := serve(t, http.MethodGet, "/../go.mod")
	if rec.Code != http.StatusMovedPermanently || rec.Header().Get("Location") != "/go.mod" {
		t.Errorf("status %d, Location %q; want 301 to /go.mod", rec.Code, rec.Header().Get("Location"))
	}
}
