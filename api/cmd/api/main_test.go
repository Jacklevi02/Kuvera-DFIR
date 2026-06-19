package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"
)

func TestRunShutsDownOnContextCancel(t *testing.T) {
	t.Parallel()

	// slog.DiscardHandler is the zero-allocation discard handler added in Go 1.24.
	logger := slog.New(slog.DiscardHandler)
	ctx, cancel := context.WithCancel(context.Background())

	done := make(chan error, 1)
	go func() { done <- run(ctx, logger) }()

	cancel()

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run returned unexpected error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("run did not return within 2s of context cancellation")
	}
}
