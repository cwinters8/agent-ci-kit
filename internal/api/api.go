// Package api serves the todo store over HTTP as JSON.
package api

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"example.com/todoapi/internal/store"
)

// maxBodyBytes bounds a request body. A todo is a title and a flag; anything
// bigger than this is a mistake or an attack.
const maxBodyBytes = 1 << 16

// New returns the HTTP handler for the API.
func New(s *store.Store, log *slog.Logger) http.Handler {
	h := &handler{store: s}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", h.health)
	mux.HandleFunc("GET /todos", h.list)
	mux.HandleFunc("POST /todos", h.create)
	mux.HandleFunc("GET /todos/{id}", h.get)
	mux.HandleFunc("PATCH /todos/{id}", h.update)
	mux.HandleFunc("DELETE /todos/{id}", h.delete)
	return logRequests(log, jsonMuxErrors(mux))
}

// jsonMuxErrors replaces the mux's plain-text 404 and 405 responses with the
// API's JSON error body. The mux writes those itself, so handlers never see
// the request. The 405 keeps the Allow header the mux computed.
func jsonMuxErrors(mux *http.ServeMux) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Handler would canonicalize "*" into a redirect; the mux itself
		// answers asterisk-form requests with 400.
		if r.RequestURI == "*" {
			writeError(w, http.StatusBadRequest, "bad request")
			return
		}
		h, pattern := mux.Handler(r)
		if pattern != "" {
			// ServeHTTP, not h: only the mux populates r.PathValue.
			mux.ServeHTTP(w, r)
			return
		}
		c := &captureWriter{header: http.Header{}, status: http.StatusOK}
		h.ServeHTTP(c, r)
		switch c.status {
		case http.StatusNotFound:
			writeError(w, http.StatusNotFound, "not found")
		case http.StatusMethodNotAllowed:
			if allow := c.header.Get("Allow"); allow != "" {
				w.Header().Set("Allow", allow)
			}
			writeError(w, http.StatusMethodNotAllowed, "method not allowed")
		default:
			// Redirects for unclean paths: replay the mux's own response.
			for k, v := range c.header {
				w.Header()[k] = v
			}
			w.WriteHeader(c.status)
			_, _ = w.Write(c.body)
		}
	})
}

// captureWriter records a response so jsonMuxErrors can inspect it.
type captureWriter struct {
	header http.Header
	status int
	body   []byte
}

func (c *captureWriter) Header() http.Header { return c.header }

func (c *captureWriter) WriteHeader(code int) { c.status = code }

func (c *captureWriter) Write(b []byte) (int, error) {
	c.body = append(c.body, b...)
	return len(b), nil
}

type handler struct {
	store *store.Store
}

type errorBody struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, errorBody{Error: msg})
}

// writeStoreError maps store errors to status codes. Anything unrecognized is
// a 500 with a generic message, so internal details never reach a client.
func writeStoreError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, store.ErrEmptyTitle), errors.Is(err, store.ErrTitleTooLong):
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

func decode(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return false
	}
	// A request holds exactly one JSON value; anything after it is an error.
	if _, err := dec.Token(); err != io.EOF {
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return false
	}
	return true
}

func pathID(w http.ResponseWriter, r *http.Request) (int, bool) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil || id < 1 {
		writeError(w, http.StatusBadRequest, "id must be a positive integer")
		return 0, false
	}
	return id, true
}

func (h *handler) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	var done *bool
	if v := r.URL.Query().Get("done"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			writeError(w, http.StatusBadRequest, "done must be true or false")
			return
		}
		done = &b
	}
	writeJSON(w, http.StatusOK, h.store.List(done))
}

func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Title string `json:"title"`
	}
	if !decode(w, r, &body) {
		return
	}
	t, err := h.store.Create(body.Title)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	w.Header().Set("Location", "/todos/"+strconv.Itoa(t.ID))
	writeJSON(w, http.StatusCreated, t)
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	t, err := h.store.Get(id)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (h *handler) update(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var p store.Patch
	if !decode(w, r, &p) {
		return
	}
	t, err := h.store.Update(id, p)
	if err != nil {
		writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := h.store.Delete(id); err != nil {
		writeStoreError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}
