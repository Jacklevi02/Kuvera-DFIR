// Command operator is the entrypoint for the Kuvera Kubernetes operator.
//
// It wires up structured logging and a graceful shutdown loop. Later tickets
// attach the Kubebuilder manager, ForensicCapture controller, and bundle
// sealing logic.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := run(ctx, logger); err != nil {
		logger.Error("operator exited", slog.Any("error", err))
		os.Exit(1)
	}
}

// run holds the operator lifecycle. Separated from main so it can be tested
// without spawning a process.
func run(ctx context.Context, logger *slog.Logger) error {
	logger.Info("kuvera operator starting", slog.String("component", "operator"))
	<-ctx.Done()
	logger.Info("kuvera operator shutting down", slog.String("component", "operator"))
	return nil
}
