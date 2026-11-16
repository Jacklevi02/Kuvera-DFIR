// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

#define FILENAME_LEN 256

// One exec event. Largest fields first so there are no implicit padding holes.
// T2.3's Go decoder reads this byte for byte: change it and update both.
struct event {
	__u64 cgroup_id;
	__u32 pid;           // kernel pid: the thread ID
	__u32 tgid;          // kernel tgid: what userspace calls the PID
	__u32 filename_len;  // true length incl. NUL; > FILENAME_LEN means truncated
	__u32 _pad;          // explicit, so the u64 alignment hole is visible and zeroed
	char comm[TASK_COMM_LEN];
	char filename[FILENAME_LEN];
};

_Static_assert(sizeof(struct event) == 296, "struct event layout changed");

// Ring buffer shared by all CPUs; userspace (T2.3) drains it.
// Size is in bytes: a power of two and a page multiple. 256 KiB holds ~860
// events (296 B + 8 B header each); when full, reserve fails and the event drops.
struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} events SEC(".maps");

char LICENSE[] SEC("license") = "Dual BSD/GPL";