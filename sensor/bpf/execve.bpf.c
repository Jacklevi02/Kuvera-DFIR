// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>

#define FILENAME_LEN 256

// One exec event. Largest fields first so there are no implicit padding holes.
// T2.3's Go decoder reads this byte for byte: change it and update both.
struct event
{
	__u64 cgroup_id;
	__u32 pid;			// kernel pid: the thread ID
	__u32 tgid;			// kernel tgid: what userspace calls the PID
	__u32 filename_len; // true length incl. NUL; > FILENAME_LEN means truncated
	__u32 _pad;			// explicit, so the u64 alignment hole is visible and zeroed
	char comm[TASK_COMM_LEN];
	char filename[FILENAME_LEN];
};

_Static_assert(sizeof(struct event) == 296, "struct event layout changed");

// Ring buffer shared by all CPUs; userspace (T2.3) drains it.
// Size is in bytes: a power of two and a page multiple. 256 KiB holds ~860
// events (296 B + 8 B header each); when full, reserve fails and the event drops.
struct
{
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} events SEC(".maps");

// Runs after every successful exec on the host, in the new program's context.
SEC("tp/sched/sched_process_exec")
int handle_exec(struct trace_event_raw_sched_process_exec *ctx)
{
	struct event *e;

	// Space comes straight from the ring buffer: the event never sits on the
	// 512-byte BPF stack. NULL means the buffer is full, so this event drops.
	e = bpf_ringbuf_reserve(&events, sizeof(*e), 0);
	if (!e)
		return 0;

	// Reserved memory holds old events' bytes; zero it so none leak (#15).
	__builtin_memset(e, 0, sizeof(*e));

	// Helpers read from "current": the task that just exec'd.
	struct task_struct *task = (struct task_struct *)bpf_get_current_task();
	__u64 pid_tgid = bpf_get_current_pid_tgid();

	e->pid = (__u32)pid_tgid; // low 32 bits; tgid is the high 32
	// CO-RE: the tgid offset is relocated to the running kernel at load.
	e->tgid = BPF_CORE_READ(task, tgid);
	e->cgroup_id = bpf_get_current_cgroup_id();
	bpf_get_current_comm(e->comm, sizeof(e->comm));

	// filename sits in the record's variable tail. __data_loc packs
	// (length << 16) | offset, with offset counted from the start of ctx.
	__u32 loc = ctx->__data_loc_filename;
	e->filename_len = loc >> 16;
	// Bounded by our buffer, not the record's length. If the read fails the
	// event is still sent: a known exec with no path beats no record.
	bpf_probe_read_kernel_str(e->filename, sizeof(e->filename),
							  (void *)ctx + (loc & 0xFFFF));

	// Every reserved record must be submitted or discarded, or the verifier
	// rejects the program.
	bpf_ringbuf_submit(e, 0);
	return 0;
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";