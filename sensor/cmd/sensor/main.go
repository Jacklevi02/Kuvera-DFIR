// Command sensor is the entrypoint for the Kuvera eBPF sensor DaemonSet.
//
// It wires up structured logging and a graceful shutdown loop. Later tickets
// attach the eBPF loader (cilium/ebpf), ring-buffer reader, and UNIX-socket
// event shipper.
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
		logger.Error("sensor exited", slog.Any("error", err))
		os.Exit(1)
	}
}

// run holds the sensor lifecycle. Separated from main so it can be tested
// without spawning a process.
func run(ctx context.Context, logger *slog.Logger) error {
	logger.Info("kuvera sensor starting", slog.String("component", "sensor"))
	<-ctx.Done()
	logger.Info("kuvera sensor shutting down", slog.String("component", "sensor"))
	return nil
}
