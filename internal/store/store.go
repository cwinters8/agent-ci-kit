// Package store holds todos in memory. It is deliberately simple: the point of
// this repo is the agent CI around it, not the persistence layer.
package store

import (
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
)

// ErrNotFound is returned when no todo has the requested ID.
var ErrNotFound = errors.New("todo not found")

// ErrEmptyTitle is returned when a todo would be created or renamed to a blank title.
var ErrEmptyTitle = errors.New("title must not be empty")

// MaxTitleLen bounds a title in characters, so one request cannot grow the
// store without limit.
const MaxTitleLen = 200

// ErrTitleTooLong is returned when a title exceeds MaxTitleLen.
var ErrTitleTooLong = errors.New("title too long")

// Todo is a single item.
type Todo struct {
	ID        int       `json:"id"`
	Title     string    `json:"title"`
	Done      bool      `json:"done"`
	CreatedAt time.Time `json:"created_at"`
}

// Patch is a partial update. Nil fields are left unchanged.
type Patch struct {
	Title *string `json:"title"`
	Done  *bool   `json:"done"`
}

// Store is safe for concurrent use.
type Store struct {
	mu     sync.RWMutex
	nextID int
	todos  map[int]Todo
	now    func() time.Time
}

// New returns an empty store.
func New() *Store {
	return &Store{nextID: 1, todos: make(map[int]Todo), now: time.Now}
}

func validTitle(title string) (string, error) {
	title = strings.TrimSpace(title)
	if title == "" {
		return "", ErrEmptyTitle
	}
	if len([]rune(title)) > MaxTitleLen {
		return "", ErrTitleTooLong
	}
	return title, nil
}

// Create adds a todo and returns it with its assigned ID.
func (s *Store) Create(title string) (Todo, error) {
	title, err := validTitle(title)
	if err != nil {
		return Todo{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	t := Todo{ID: s.nextID, Title: title, CreatedAt: s.now().UTC()}
	s.todos[t.ID] = t
	s.nextID++
	return t, nil
}

// Get returns the todo with the given ID.
func (s *Store) Get(id int) (Todo, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	t, ok := s.todos[id]
	if !ok {
		return Todo{}, ErrNotFound
	}
	return t, nil
}

// List returns every todo, oldest first. When done is non-nil, only todos with
// that Done value are returned.
func (s *Store) List(done *bool) []Todo {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Todo, 0, len(s.todos))
	for _, t := range s.todos {
		if done != nil && t.Done != *done {
			continue
		}
		out = append(out, t)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// Update applies a patch and returns the updated todo.
func (s *Store) Update(id int, p Patch) (Todo, error) {
	var title string
	if p.Title != nil {
		var err error
		if title, err = validTitle(*p.Title); err != nil {
			return Todo{}, err
		}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.todos[id]
	if !ok {
		return Todo{}, ErrNotFound
	}
	if p.Title != nil {
		t.Title = title
	}
	if p.Done != nil {
		t.Done = *p.Done
	}
	s.todos[id] = t
	return t, nil
}

// Delete removes the todo with the given ID.
func (s *Store) Delete(id int) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.todos[id]; !ok {
		return ErrNotFound
	}
	delete(s.todos, id)
	return nil
}
