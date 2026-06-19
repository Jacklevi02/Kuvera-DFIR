// Command api is the entrypoint for the Kuvera gRPC + REST API gateway.
//
// It wires up structured logging and a graceful shutdown loop. Later tickets
// attach the gRPC server, REST gateway (grpc-gateway), and storage clients.
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
		logger.Error("api exited", slog.Any("error", err))
		os.Exit(1)
	}
}

// run holds the API server lifecycle. Separated from main so it can be tested
// without spawning a process.
func run(ctx context.Context, logger *slog.Logger) error {
	logger.Info("kuvera api starting", slog.String("component", "api"))
	<-ctx.Done()
	logger.Info("kuvera api shutting down", slog.String("component", "api"))
	return nil
}
