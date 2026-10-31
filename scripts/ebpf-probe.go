// Loads the smallest valid eBPF program, to prove the kernel accepts one from
// wherever this binary runs. CI runs it inside a kind node. It exits non-zero if
// the load is refused, as it is for an unprivileged user or under rootless Docker.
//
// The program is a tracepoint, like the sensor's, because the kernel requires
// privilege to load one. It is loaded and never attached.
//
// This is a raw syscall so the check needs no module: sensor/go.mod has no
// dependencies yet. The sensor itself loads through cilium/ebpf.
//
//	CGO_ENABLED=0 go build -o ebpf-probe scripts/ebpf-probe.go
package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

const (
	sysBPF                = 321 // x86-64 only; the syscall package does not define it.
	bpfProgLoad           = 5
	bpfProgTypeTracepoint = 5
)

// r0 = 0; exit. Package-level so the addresses in progLoadAttr stay valid.
var (
	instructions = [2]uint64{0xb7, 0x95}
	license      = [4]byte{'G', 'P', 'L', 0}
)

// progLoadAttr is the start of union bpf_attr for BPF_PROG_LOAD. The kernel
// treats the fields left out as zero.
type progLoadAttr struct {
	progType uint32
	insnCnt  uint32
	insns    uint64
	license  uint64
}

func main() {
	attr := progLoadAttr{
		progType: bpfProgTypeTracepoint,
		insnCnt:  uint32(len(instructions)),
		insns:    uint64(uintptr(unsafe.Pointer(&instructions))),
		license:  uint64(uintptr(unsafe.Pointer(&license))),
	}
	fd, _, errno := syscall.Syscall(sysBPF, bpfProgLoad, uintptr(unsafe.Pointer(&attr)), unsafe.Sizeof(attr))
	if errno != 0 {
		fmt.Fprintf(os.Stderr, "eBPF program refused: %v\n", errno)
		os.Exit(1)
	}
	fmt.Printf("eBPF program loaded (fd %d)\n", fd)
}
