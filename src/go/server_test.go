package main

import (
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func stubSoftware() []Software {
	return []Software{{Name: "Example App", Version: "1.2.3"}}
}

// stubExecutables returns one file per wanted category, so tests can see
// which categories were asked for.
func stubExecutables(want map[string]bool) []Executable {
	var list []Executable
	for _, name := range categoryNames(want) {
		list = append(list, Executable{Name: "file", Directory: "/dir", Size: 1234, Modified: "2026-01-02T03:04:05+08:00", Category: name})
	}
	return list
}

func serve(t *testing.T, method, target string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	newHandler(stubSoftware, stubExecutables).ServeHTTP(rec, httptest.NewRequest(method, target, nil))
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

func TestHostAPI(t *testing.T) {
	rec := serve(t, http.MethodGet, "/api/host")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200", rec.Code)
	}
	var body struct {
		ComputerName string   `json:"computerName"`
		IPAddresses  []string `json:"ipAddresses"`
		GeneratedAt  string   `json:"generatedAt"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if body.ComputerName != computerName() {
		t.Errorf("computerName = %q, want %q", body.ComputerName, computerName())
	}
	if body.GeneratedAt == "" {
		t.Error("generatedAt is empty")
	}
	if body.IPAddresses == nil {
		t.Errorf("ipAddresses missing or null in %s", rec.Body.String())
	}
}

func TestSoftwareAPI(t *testing.T) {
	rec := serve(t, http.MethodGet, "/api/software")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d, want 200", rec.Code)
	}
	var body map[string]json.RawMessage
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	// Only the host tag: the IP addresses are in /api/host
	for _, key := range []string{"computerName", "generatedAt", "items"} {
		if _, ok := body[key]; !ok {
			t.Errorf("%s missing in %s", key, rec.Body.String())
		}
	}
	if _, ok := body["ipAddresses"]; ok {
		t.Errorf("ipAddresses should not be in %s", rec.Body.String())
	}
	var items []Software
	if err := json.Unmarshal(body["items"], &items); err != nil {
		t.Fatalf("invalid items: %v", err)
	}
	if len(items) != 1 || items[0] != stubSoftware()[0] {
		t.Errorf("items = %+v, want %+v", items, stubSoftware())
	}
}

func TestEmptySoftwareListIsArray(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler(func() []Software { return nil }, stubExecutables).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/software", nil))
	if !strings.Contains(rec.Body.String(), `"items":[]`) {
		t.Errorf("body = %s, want items to be []", rec.Body.String())
	}
}

func TestExecutablesAPI(t *testing.T) {
	tests := []struct {
		query string
		want  []string
	}{
		{"", []string{"Executable"}}, // list_executables' default
		{"?categories=executable,library", []string{"Executable", "Library"}},
		{"?categories=other,script", []string{"Script", "Other"}},
		{"?categories=all", []string{"Executable", "Library", "Script", "Installer", "Other"}},
	}
	for _, tt := range tests {
		rec := serve(t, http.MethodGet, "/api/executables"+tt.query)
		if rec.Code != http.StatusOK {
			t.Errorf("%s: status %d, want 200", tt.query, rec.Code)
			continue
		}
		var body struct {
			ComputerName string       `json:"computerName"`
			GeneratedAt  string       `json:"generatedAt"`
			Categories   []string     `json:"categories"`
			Items        []Executable `json:"items"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("%s: invalid JSON: %v", tt.query, err)
		}
		if body.GeneratedAt == "" {
			t.Errorf("%s: generatedAt is empty", tt.query)
		}
		if strings.Join(body.Categories, ",") != strings.Join(tt.want, ",") {
			t.Errorf("%s: categories = %v, want %v", tt.query, body.Categories, tt.want)
		}
		if len(body.Items) != len(tt.want) {
			t.Errorf("%s: %d items, want %d", tt.query, len(body.Items), len(tt.want))
		}
	}
	if rec := serve(t, http.MethodGet, "/api/executables"); !strings.Contains(rec.Body.String(), `"Size":1234`) {
		t.Errorf("Size is not a number in %s", rec.Body.String())
	}
}

func TestExecutablesAPIRejectsBadCategories(t *testing.T) {
	for _, query := range []string{"?categories=", "?categories=scripts", "?categories=executable,foo"} {
		rec := serve(t, http.MethodGet, "/api/executables"+query)
		if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), `"error"`) {
			t.Errorf("%s: status %d, body %s; want 400 with an error", query, rec.Code, rec.Body.String())
		}
	}
}

func TestEmptyExecutablesListIsArray(t *testing.T) {
	rec := httptest.NewRecorder()
	newHandler(stubSoftware, func(map[string]bool) []Executable { return nil }).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/executables", nil))
	if !strings.Contains(rec.Body.String(), `"items":[]`) {
		t.Errorf("body = %s, want items to be []", rec.Body.String())
	}
}

func TestSortExecutables(t *testing.T) {
	list := []Executable{
		{Name: "b", Directory: "/x"},
		{Name: "B", Directory: "/x"},
		{Name: "a", Directory: "/y"},
		{Name: "c", Directory: "/X"},
		{Name: "b", Directory: "/x"},
	}
	names := func(l []Executable) string {
		var s []string
		for _, e := range l {
			s = append(s, e.Directory+"/"+e.Name)
		}
		return strings.Join(s, " ")
	}
	// Byte-wise, like LC_ALL=C sort -u on Linux
	if got, want := names(sortExecutables(append([]Executable{}, list...), strings.Compare)), "/X/c /x/B /x/b /y/a"; got != want {
		t.Errorf("byte-wise: got %s, want %s", got, want)
	}
	// Case-insensitive, as on Windows, where B and b are the same file: the
	// first one found is kept
	fold := func(a, b string) int { return strings.Compare(strings.ToLower(a), strings.ToLower(b)) }
	if got, want := names(sortExecutables(append([]Executable{}, list...), fold)), "/x/b /X/c /y/a"; got != want {
		t.Errorf("case-insensitive: got %s, want %s", got, want)
	}
}

func TestIPAddressesSkipLoopbackAndLinkLocal(t *testing.T) {
	ips := ipAddresses()
	if ips == nil {
		t.Fatal("ipAddresses() = nil, want an empty or filled slice")
	}
	seenV6 := false
	for _, s := range ips {
		ip := net.ParseIP(s)
		if ip == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
			t.Errorf("unexpected address %q in %v", s, ips)
			continue
		}
		if ip.To4() == nil {
			seenV6 = true
		} else if seenV6 {
			t.Errorf("IPv4 %q listed after an IPv6 address in %v", s, ips)
		}
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
		{http.MethodPost, "/api/host", http.StatusMethodNotAllowed},
		{http.MethodPost, "/api/software", http.StatusMethodNotAllowed},
		{http.MethodPost, "/api/executables", http.StatusMethodNotAllowed},
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
