package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"example.com/todoapi/internal/store"
)

func newServer(t *testing.T) *httptest.Server {
	t.Helper()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	srv := httptest.NewServer(New(store.New(), log))
	t.Cleanup(srv.Close)
	return srv
}

func do(t *testing.T, srv *httptest.Server, method, path, body string) (*http.Response, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, srv.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp, b
}

func TestHealth(t *testing.T) {
	srv := newServer(t)
	resp, body := do(t, srv, "GET", "/healthz", "")
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), `"ok"`) {
		t.Fatalf("got %d %s", resp.StatusCode, body)
	}
}

func TestCreateGetListUpdateDelete(t *testing.T) {
	srv := newServer(t)

	resp, body := do(t, srv, "POST", "/todos", `{"title":"write tests"}`)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("create: %d %s", resp.StatusCode, body)
	}
	if loc := resp.Header.Get("Location"); loc != "/todos/1" {
		t.Fatalf("Location = %q", loc)
	}
	var created store.Todo
	if err := json.Unmarshal(body, &created); err != nil || created.Title != "write tests" {
		t.Fatalf("create body: %s (%v)", body, err)
	}

	resp, _ = do(t, srv, "GET", "/todos/1", "")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("get: %d", resp.StatusCode)
	}

	resp, body = do(t, srv, "PATCH", "/todos/1", `{"done":true}`)
	var updated store.Todo
	json.Unmarshal(body, &updated)
	if resp.StatusCode != http.StatusOK || !updated.Done || updated.Title != "write tests" {
		t.Fatalf("patch: %d %s", resp.StatusCode, body)
	}

	resp, body = do(t, srv, "GET", "/todos?done=true", "")
	var list []store.Todo
	json.Unmarshal(body, &list)
	if resp.StatusCode != http.StatusOK || len(list) != 1 {
		t.Fatalf("list done: %d %s", resp.StatusCode, body)
	}

	resp, _ = do(t, srv, "DELETE", "/todos/1", "")
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("delete: %d", resp.StatusCode)
	}
	resp, _ = do(t, srv, "GET", "/todos/1", "")
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("get after delete: %d", resp.StatusCode)
	}
}

func TestEmptyListIsArrayNotNull(t *testing.T) {
	srv := newServer(t)
	_, body := do(t, srv, "GET", "/todos", "")
	if strings.TrimSpace(string(body)) != "[]" {
		t.Fatalf("got %s; want []", body)
	}
}

func TestBadRequests(t *testing.T) {
	srv := newServer(t)
	cases := []struct {
		name, method, path, body string
		want                     int
	}{
		{"malformed JSON", "POST", "/todos", `{"title":`, http.StatusBadRequest},
		{"unknown field", "POST", "/todos", `{"title":"x","owner":"me"}`, http.StatusBadRequest},
		{"blank title", "POST", "/todos", `{"title":"  "}`, http.StatusUnprocessableEntity},
		{"non-numeric id", "GET", "/todos/abc", "", http.StatusBadRequest},
		{"zero id", "GET", "/todos/0", "", http.StatusBadRequest},
		{"missing id", "GET", "/todos/42", "", http.StatusNotFound},
		{"bad done filter", "GET", "/todos?done=maybe", "", http.StatusBadRequest},
		{"oversized body", "POST", "/todos", `{"title":"` + strings.Repeat("a", maxBodyBytes) + `"}`, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resp, body := do(t, srv, tc.method, tc.path, tc.body)
			if resp.StatusCode != tc.want {
				t.Fatalf("got %d %s; want %d", resp.StatusCode, body, tc.want)
			}
			if !strings.Contains(resp.Header.Get("Content-Type"), "application/json") {
				t.Fatalf("error response is not JSON: %q", resp.Header.Get("Content-Type"))
			}
		})
	}
}
