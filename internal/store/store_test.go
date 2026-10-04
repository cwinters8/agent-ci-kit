package store

import (
	"errors"
	"strings"
	"sync"
	"testing"
)

func ptr[T any](v T) *T { return &v }

func TestCreateAssignsIncreasingIDs(t *testing.T) {
	s := New()
	a, _ := s.Create("first")
	b, _ := s.Create("second")
	if a.ID != 1 || b.ID != 2 {
		t.Fatalf("got IDs %d, %d; want 1, 2", a.ID, b.ID)
	}
}

func TestCreateTrimsAndValidatesTitle(t *testing.T) {
	s := New()
	got, err := s.Create("  milk  ")
	if err != nil || got.Title != "milk" {
		t.Fatalf("Create = %+v, %v; want title %q", got, err, "milk")
	}
	if _, err := s.Create("   "); !errors.Is(err, ErrEmptyTitle) {
		t.Fatalf("blank title: err = %v; want ErrEmptyTitle", err)
	}
	if _, err := s.Create(strings.Repeat("a", MaxTitleLen+1)); !errors.Is(err, ErrTitleTooLong) {
		t.Fatalf("long title: err = %v; want ErrTitleTooLong", err)
	}
}

func TestListFiltersAndSorts(t *testing.T) {
	s := New()
	for _, title := range []string{"a", "b", "c"} {
		s.Create(title)
	}
	s.Update(2, Patch{Done: ptr(true)})

	all := s.List(nil)
	if len(all) != 3 || all[0].ID != 1 || all[2].ID != 3 {
		t.Fatalf("List(nil) = %+v; want 3 todos sorted by ID", all)
	}
	done := s.List(ptr(true))
	if len(done) != 1 || done[0].ID != 2 {
		t.Fatalf("List(done) = %+v; want only ID 2", done)
	}
	open := s.List(ptr(false))
	if len(open) != 2 {
		t.Fatalf("List(open) = %+v; want 2 todos", open)
	}
}

func TestUpdateLeavesNilFieldsAlone(t *testing.T) {
	s := New()
	s.Create("keep me")
	got, err := s.Update(1, Patch{Done: ptr(true)})
	if err != nil || got.Title != "keep me" || !got.Done {
		t.Fatalf("Update = %+v, %v", got, err)
	}
}

func TestUpdateRejectsBlankTitleWithoutWriting(t *testing.T) {
	s := New()
	s.Create("original")
	if _, err := s.Update(1, Patch{Title: ptr(" "), Done: ptr(true)}); !errors.Is(err, ErrEmptyTitle) {
		t.Fatalf("err = %v; want ErrEmptyTitle", err)
	}
	got, _ := s.Get(1)
	if got.Title != "original" || got.Done {
		t.Fatalf("rejected patch was partly applied: %+v", got)
	}
}

func TestMissingIDs(t *testing.T) {
	s := New()
	if _, err := s.Get(9); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get: %v", err)
	}
	if _, err := s.Update(9, Patch{}); !errors.Is(err, ErrNotFound) {
		t.Errorf("Update: %v", err)
	}
	if err := s.Delete(9); !errors.Is(err, ErrNotFound) {
		t.Errorf("Delete: %v", err)
	}
}

func TestConcurrentCreates(t *testing.T) {
	s := New()
	var wg sync.WaitGroup
	for range 100 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			s.Create("x")
		}()
	}
	wg.Wait()
	if n := len(s.List(nil)); n != 100 {
		t.Fatalf("got %d todos; want 100", n)
	}
}
