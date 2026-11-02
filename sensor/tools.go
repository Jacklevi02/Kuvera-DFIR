//go:build tools

// Package tools keeps the cilium/ebpf pin in go.mod until T2.3 adds the first
// real import. Without an import, go mod tidy would drop it. Delete this file
// then.
package tools

import _ "github.com/cilium/ebpf"
