# sensor/bpf

The sensor's eBPF programs, written in C with CO-RE. Why each tool and flag is
pinned is explained in [ADR 0001](../../docs/adr/0001-ebpf-toolchain.md).

| File            | What it is                                                     |
| --------------- | -------------------------------------------------------------- |
| `execve.bpf.c`  | Records every successful exec as an event in a ring buffer     |
| `vmlinux.h`     | Snapshot of the kernel's types, generated, never edited        |
| `Makefile`      | Builds `build/*.bpf.o`, fetches libbpf headers, regenerates `vmlinux.h` |
| `LICENSE*`      | Dual GPL-2.0-only / BSD-2-Clause for the C here (not `vmlinux.h`) |

## Building

```bash
make -C sensor/bpf           # compile each *.bpf.c to build/*.bpf.o
make -C sensor/bpf clean     # remove build/
```

`-C sensor/bpf` makes `make` change into `sensor/bpf/` before reading its
`Makefile`, so you can run it from the repo root. Running `make` inside
`sensor/bpf/` does the same thing. Paths in this Makefile, such as `build/`, are
relative to `sensor/bpf/`. The root `make clean` also removes `sensor/bpf/build/`.

The first build downloads the libbpf headers (`bpf_helpers.h`,
`bpf_core_read.h` and others) into `build/libbpf-<version>/` and checks their
SHA-256. clang is `clang-<major>` from `mise.toml`, and the build refuses any
other version. Each flag is explained in the Makefile. The two that matter most
here are:

- **`-g`** emits BTF. Map definitions and CO-RE relocations are carried in
  BTF, so without it nothing loads.
- **`-Wall -Werror`**: any warning fails the build.

## vmlinux.h

`vmlinux.h` holds every type definition in the kernel, such as
`struct task_struct`, the tracepoint record structs, `__u32` and `pid_t`. It's
dumped from the kernel's own BTF and replaces the `linux/*.h` headers. Don't mix
it with those headers, because they redefine the same types.

```bash
head -3 sensor/bpf/vmlinux.h                 # which kernel it came from
make -C sensor/bpf vmlinux                   # regenerate from the running kernel
```

`make vmlinux` runs `bpftool btf dump file /sys/kernel/btf/vmlinux format c`.
It's a manual step whose result is committed, never a build step, because the
output depends on whoever's machine runs it. Regenerate only when a program
needs a type the snapshot lacks (see [TOOLCHAIN.md](../../docs/TOOLCHAIN.md)).

The snapshot doesn't have to match the kernel the program runs on. Line 8
applies `preserve_access_index` to every struct, so each field access is
recorded as a CO-RE relocation, which libbpf fixes up at load time. A real
example: the snapshot is from Linux 7.2.13, where `task_struct.tgid` is at byte
2876. On 7.3.3, libbpf patched it to 2940.

Include `vmlinux.h` first, before the libbpf headers, which use its types
without defining them.

## Tracepoint format files

A tracepoint program's `ctx` points at a record whose layout the kernel
publishes:

```bash
sudo cat /sys/kernel/tracing/events/sched/sched_process_exec/format
grep -n -A6 'struct trace_event_raw_sched_process_exec {' sensor/bpf/vmlinux.h
```

The second command shows the same layout as a C struct, which is the type of
`ctx`. On Linux 7.2/7.3 the format is:

```
field:unsigned short common_type;   offset:0;  size:2   ┐
field:unsigned char common_flags;   offset:2;  size:1   │ header on every record
field:unsigned char common_preempt_count; offset:3; size:1 │ (struct trace_entry)
field:int common_pid;               offset:4;  size:4   ┘
field:__data_loc char[] filename;   offset:8;  size:4
field:pid_t pid;                    offset:12; size:4
field:pid_t old_pid;                offset:16; size:4
```

`__data_loc` means the string isn't stored in the field itself. The field is a
`u32` locator, and the string sits in the record's variable-length tail:

```
 31            16 15             0
┌────────────────┬────────────────┐
│ length (+NUL)  │ offset from ctx│
└────────────────┴────────────────┘
```

For example, `/usr/bin/ls` is stored as `(12 << 16) | 20`, with the string at
`ctx + 20`. The offset isn't known until runtime, so the verifier won't let the
program dereference it. It has to be read with `bpf_probe_read_kernel_str`.
(Some kernels' format files use `__rel_loc`, where the offset is relative to the
field rather than to `ctx`.)

## execve.bpf.c

Attached to `sched/sched_process_exec`, which fires once per successful exec,
host-wide, inside the task that exec'd, after the new program image has been
set up.

### The event

```
offset  size  field          source
0       8     cgroup_id      bpf_get_current_cgroup_id()
8       4     pid            bpf_get_current_pid_tgid(), low 32 bits
12      4     tgid           BPF_CORE_READ(task, tgid)
16      4     filename_len   ctx->__data_loc_filename >> 16
20      4     _pad           always 0
24      16    comm           bpf_get_current_comm()
40      256   filename       bpf_probe_read_kernel_str(ctx + offset)
296           total
```

- **Field order:** largest first, so the compiler adds no padding. `_pad` makes
  the last 4 bytes explicit. A `_Static_assert` fails the build if the size
  changes, because the Go decoder (T2.3) reads this byte for byte.
- **IDs:** kernel `pid` is the thread ID, and `tgid` is what userspace calls
  the PID. Both are host (initial PID namespace) IDs, not what `ps` shows in a
  container.
- **Truncation:** `filename_len` is the path's true length, including the NUL.
  If it's greater than 256, `filename` holds the first 255 bytes and a NUL.
- **Failed read:** a non-zero `filename_len` with an empty `filename` means the
  read failed. The event is still sent, because a known exec with no path is
  better evidence than no record.

### The map

`events` is a `BPF_MAP_TYPE_RINGBUF` of 256 KiB, shared by all CPUs and kept
in commit order. A ring buffer's `max_entries` is a size in bytes, and must be
a power of two and a multiple of the page size. Each record takes 296 bytes
plus an 8-byte header, so the buffer holds about 860 records. When it's full,
reserve fails and the event is dropped. Counting drops is T3.7.

### The handler

1. **`bpf_ringbuf_reserve`** returns space inside the buffer, so the 296-byte
   event never sits on the 512-byte BPF stack. The size must be a constant.
2. **The NULL check** is required by the verifier, and NULL means the buffer
   is full.
3. **`__builtin_memset`** zeroes the record. Reserved memory still holds
   earlier events, and `bpf_probe_read_kernel_str` doesn't clear the bytes
   after the NUL.
4. **Fill:** helpers read "current", which is the task that exec'd. `tgid` goes
   through `BPF_CORE_READ` as a CO-RE example. `filename` uses the `__data_loc`
   offset.
5. **`bpf_ringbuf_submit`** publishes the record. The verifier rejects any path
   that reserves without a submit or a discard.

`bpf_probe_read_kernel` (behind `BPF_CORE_READ`) and `bpf_probe_read_kernel_str`
are GPL-only, which is why `LICENSE` must be `"Dual BSD/GPL"`.

### Observed behaviour

Tested on Linux 7.3.3 (Fedora 44), 2026-11-16:

- **`pid == tgid` on every event.** When a non-leader thread calls exec, the
  kernel kills the other threads and the exec'ing thread takes over the
  leader's ID. A Python thread with ID 67535 exec'd, and the event reported
  `pid=tgid=67534`. The thread's original ID is only in the tracepoint's
  `old_pid` field, which isn't recorded.
- **`comm` is already the new program's name**, such as `true`, not `python3`.
- **For a `#!` script, `comm` is the script's name** (`cpuUsage.sh`), not the
  interpreter's. `comm` can also be changed later by the process itself, so
  treat it as a label, not as proof.

- **`filename_len` counts the NUL.** `/usr/bin/sed` (12 characters) gives
  `len=13`.
- **`filename` is the path exactly as passed to exec, unresolved.** Running
  `/bin/sh` records `/bin/sh`, although on Fedora `/bin` is a symlink and `sh`
  is `bash`. Paths only look absolute because the shell searched `PATH` before
  calling exec.
- **For a `#!` script, `filename` is the script's path.** The interpreter
  appears in neither `filename` nor `comm`.

- **Relative paths are kept as typed.** `cd /usr/bin && ./ls` records `./ls`,
  which means nothing without the process's working directory.
- **`fexecve` loses the path.** Exec'ing an open file descriptor records
  `/dev/fd/3`. This is also how fileless execution (`memfd_create` plus
  `fexecve`) looks.
- **Truncation is detectable.** A 309-character path recorded `len=310`. Whether
  `filename` then holds exactly 255 bytes still needs a byte-level check (T2.3,
  T2.5).

So `filename` is what the caller asked to run, not proof of which binary on disk
ran. Identifying the binary itself (inode, device, or hash) is a later design
question.

## Inspecting a compiled object

These read the `.o` file on disk, so they don't need root. `bpftool` is pinned
in `mise.toml`. `pahole` (from the `dwarves` package) and `readelf` (from
`binutils`) come from your distribution and aren't pinned, so use them only by
hand, not in scripts or CI. Both have man pages.

### Struct layout: `pahole`

```bash
pahole -C event sensor/bpf/build/execve.bpf.o
```

- **`-C <name>`**: print only this struct. Without it, pahole prints every
  struct.

This prints each field's offset and size, as `/* offset size */`, plus the
total. Padding added by the compiler shows up as `/* XXX N bytes hole */`, and
there shouldn't be any. clang drops types that nothing uses, so a struct only
appears once a program uses it.

The pinned equivalent, which is harder to read:

```bash
bpftool btf dump file sensor/bpf/build/execve.bpf.o | grep -A8 "STRUCT 'event'"
```

### ELF sections: `readelf`

```bash
readelf -S -W sensor/bpf/build/execve.bpf.o      # -S: section headers, -W: don't truncate names
readelf -x license sensor/bpf/build/execve.bpf.o # -x: hex dump of one section
```

Each `SEC("...")` in the C code becomes a section with that name, and the
loader looks for these:

| Section                 | Holds                                                   |
| ----------------------- | ------------------------------------------------------- |
| `tp/<category>/<event>` | a program's instructions and its attach point          |
| `.rel<program section>` | references to maps and globals, which the loader patches |
| `.maps`                 | map definitions, read from BTF                          |
| `license`               | the licence string the kernel checks                    |
| `.rodata`               | constants, such as a `bpf_printk` format string        |
| `.BTF`                  | types, produced by `-g`                                 |
| `.BTF.ext`              | CO-RE relocations and line info                         |

### Maps: `bpftool btf dump`

```bash
bpftool btf dump file sensor/bpf/build/execve.bpf.o
```

A map's settings are stored as array sizes in BTF. The ring buffer shows up as
`nr_elems=27` (`BPF_MAP_TYPE_RINGBUF`) and `nr_elems=262144` (its size in
bytes).

## Loading a program into the kernel

Loading runs the verifier against the real kernel, which compiling can't do.

```bash
sudo "$(mise which bpftool)" -d prog load sensor/bpf/build/execve.bpf.o /sys/fs/bpf/kuvera-execve
sudo "$(mise which bpftool)" prog show pinned /sys/fs/bpf/kuvera-execve
sudo rm /sys/fs/bpf/kuvera-execve
```

- **`prog load <obj> <pin path>`** does four things, through libbpf:
  1. reads the object
  2. creates its maps
  3. patches map references and CO-RE field offsets for the running kernel,
     using `/sys/kernel/btf/vmlinux`
  4. hands the program to the kernel, where the verifier checks every path

  If the verifier accepts it, bpftool pins it in bpffs so that it outlives
  bpftool. Loading fails if the pin path already exists.
- **`-d`** prints libbpf's debug output and the full verifier log. When a load
  fails, the cause is near the end of the log.
- **`prog show pinned <path>`** confirms the kernel holds it, with its type,
  name, instruction count and map IDs.
- **`rm`** removes the pin, and the kernel then frees the program and its maps.
  Pins last until removed or until a reboot.
- **`sudo`** is needed because loading needs `CAP_BPF` and `CAP_PERFMON` (or
  root). `mise which` is there because sudo resets `PATH`, so the mise shim isn't
  found.

To see only the lines that matter:

```bash
sudo "$(mise which bpftool)" -d prog load sensor/bpf/build/execve.bpf.o /sys/fs/bpf/kuvera-execve 2>&1 \
  | grep -i -E 'CO-RE relocations|relo #|processed|error'
```

A good load of `execve.bpf.o` shows:

```
found 2 CO-RE relocations
relo #0: ... struct task_struct.tgid (0:98 @ offset 2876)
relo #0: patched insn #50 (ALU/ALU64) imm 2876 -> 2940
relo #1: ... trace_event_raw_sched_process_exec.__data_loc_filename (0:1 @ offset 8)
relo #1: patched insn #65 (LDX/ST/STX) off 8 -> 8
processed 81 insns (limit 1000000) ...
```

- **The `relo` lines:** the offset from `vmlinux.h` is followed by the offset in
  the running kernel. The two differ when the kernel has changed.
- **`processed N insns`** with no error before it means the verifier accepted
  the program.

| Proves                                                     | Doesn't prove                           |
| ---------------------------------------------------------- | --------------------------------------- |
| The verifier accepts the program                           | that it runs: it's loaded, not attached |
| The kernel supports its map types and helpers              | that events reach the ring buffer       |
| The licence check passes, and maps and relocations resolve | that field values are right             |
| It loads on this kernel                                    | that it loads on other kernels          |

The program is never attached, so loading it has no effect on the system apart
from its maps' memory, which lasts until the `rm`.

## Watching events by hand

Nothing reads the ring buffer until the Go loader exists (T2.3). To see values
before then, print them from the program temporarily and attach it.

1. Add a temporary line before `bpf_ringbuf_submit`:

   ```c
   bpf_printk("pid=%u tgid=%u comm=%s", e->pid, e->tgid, e->comm);
   bpf_printk("len=%u file=%s", e->filename_len, e->filename);
   ```

   Each `bpf_printk` takes at most 3 arguments.

2. Build, load and attach, then read the output:

   ```bash
   make -C sensor/bpf
   sudo rm -rf /sys/fs/bpf/kuvera-execve           # a leftover pin makes the load fail
   sudo "$(mise which bpftool)" prog load sensor/bpf/build/execve.bpf.o /sys/fs/bpf/kuvera-execve autoattach
   sudo cat /sys/kernel/tracing/trace_pipe          # Ctrl-C to stop; run commands in another terminal
   sudo rm -rf /sys/fs/bpf/kuvera-execve            # detach and unload
   ```

   - **`autoattach`** attaches the program to the tracepoint named by its
     `SEC()`. Without it, the program is loaded but never runs, and nothing is
     printed.
   - **`trace_pipe`** is the kernel's shared trace buffer. Reading it consumes
     it, so use one reader at a time. It's host-wide, so expect events from
     every process on the machine. Filter with `grep`.

3. Remove the `bpf_printk` lines before committing. They write file paths into
   a host-wide buffer, which breaks the rule against PII in logs.

To check a path from a test, filter the noise:

```bash
sudo cat /sys/kernel/tracing/trace_pipe | grep -E 'file=(/tmp|\./|/dev/fd)'
```

The results are in [Observed behaviour](#observed-behaviour). The pasted trace
output can lose characters, so count lengths in the shell rather than by eye,
for example with `grep -o 'file=[^ ]*' | awk '{print length($0) - 5}'`.

## On a kind node

A kind node has no kernel of its own, so a host load hits the same verifier.
Loading inside a node checks the node's environment as well. Nodes don't have
bpftool, so copy the binary in:

```bash
NODE=kuvera-dev-control-plane                # kind get nodes --name kuvera-dev
docker cp "$(mise which bpftool)" $NODE:/usr/local/bin/bpftool
docker cp sensor/bpf/build/execve.bpf.o $NODE:/root/
docker exec $NODE bpftool -d prog load /root/execve.bpf.o /sys/fs/bpf/kuvera-execve
docker exec $NODE rm /sys/fs/bpf/kuvera-execve
```

- **`docker cp`** copies files into the node container. The mise binary is
  static, so it runs there.
- **`docker exec`** runs a command inside the node, as root.

`/sys/fs/bpf` is bind-mounted from the host, so a pin left in a node also stays
on the host. A program attached in a node sees exec events from the host and
from every other node, and IDs are host IDs.

## Editor setup

VS Code's C/C++ extension doesn't read the Makefile, so it can't find
`<bpf/bpf_helpers.h>`. Point it at the same include paths as the Makefile, in
`.vscode/c_cpp_properties.json`, which is gitignored and stays local:

```json
{
  "configurations": [
    {
      "name": "eBPF",
      "includePath": [
        "${workspaceFolder}/sensor/bpf",
        "${workspaceFolder}/sensor/bpf/build/libbpf-1.8.0"
      ],
      "defines": ["__TARGET_ARCH_x86"],
      "cStandard": "gnu11",
      "intelliSenseMode": "linux-clang-x64"
    }
  ],
  "version": 4
}
```

Run `make -C sensor/bpf` once first, because that's what downloads the libbpf
headers. Update the path if `LIBBPF_VERSION` changes. The extension's parser
isn't clang, so it still flags things clang accepts, such as
`BPF_CORE_READ` ("expected a ';'") and `__uint`. If make passes but the editor
complains, trust make.
