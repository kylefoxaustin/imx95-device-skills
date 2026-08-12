# i.MX 95 Memory Architecture — Design Reference

## Overview

The i.MX 95 SoC uses LPDDR4/LPDDR5 memory with a unified physical address space shared
between the Cortex-A55 application processor cluster, the Cortex-M7 and Cortex-M33
real-time cores, the eIQ Neutron NPU, the Vivante GC7000UL GPU, the ISP (Image Signal
Processor), and the VPU (Video Processing Unit).

Because multiple hardware engines perform DMA directly into system memory, the Linux kernel
reserves large contiguous regions using the **Contiguous Memory Allocator (CMA)** at boot
time. These regions cannot be used for general-purpose allocations and are not reflected in
`MemAvailable` in `/proc/meminfo`.

---

## Physical Memory Map (typical 4 GB configuration)

```
Physical Address Space (4 GB LPDDR4/5)
┌─────────────────────────────────────────────────────────┐
│ 0x00000000 – 0x7FFFFFFF  (2 GB)                         │
│   Linux kernel + user space (MemTotal in /proc/meminfo) │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │ Kernel text + data + modules                    │   │
│   ├─────────────────────────────────────────────────┤   │
│   │ User space processes (anonymous + file-backed)  │   │
│   ├─────────────────────────────────────────────────┤   │
│   │ Page cache (file data, reclaimable)             │   │
│   ├─────────────────────────────────────────────────┤   │
│   │ CMA regions (reserved at boot, not in MemFree)  │   │
│   │  ├── cma-vpu    256 MB  (VPU encode/decode)     │   │
│   │  ├── cma-isp    128 MB  (ISP camera pipeline)   │   │
│   │  ├── cma-npu     64 MB  (NPU inference buffers) │   │
│   │  └── cma-default 64 MB  (general DMA)           │   │
│   └─────────────────────────────────────────────────┘   │
│                                                         │
│ 0x80000000 – 0xFFFFFFFF  (2 GB)                         │
│   M7 / M33 SRAM + peripheral registers                  │
│   (not accessible to Linux user space)                  │
└─────────────────────────────────────────────────────────┘
```

*Actual layout depends on U-Boot memory map and device tree `reserved-memory` nodes.*

---

## CMA (Contiguous Memory Allocator)

### What CMA Is

CMA reserves physically contiguous memory regions at boot time for hardware engines that
cannot use scatter-gather DMA (or where scatter-gather has high overhead). On i.MX 95,
the primary CMA consumers are:

| Consumer | Typical Size | Why CMA |
|----------|-------------|---------|
| VPU (video codec) | 256 MB | Requires large contiguous buffers for compressed bitstream + decoded frames |
| ISP (camera) | 128 MB | Raw sensor frames + ISP pipeline intermediate buffers |
| NPU (eIQ Neutron) | 64 MB | Model weights + activation tensors for inference |
| Default (general) | 64 MB | Catch-all for other DMA devices |

### Reading CMA State

```bash
# Aggregate (always available)
grep "^Cma" /proc/meminfo
# CmaTotal:    524288 kB   (512 MB reserved)
# CmaFree:     393216 kB   (384 MB free)

# Per-region (requires CONFIG_CMA_DEBUGFS=y and debugfs mounted)
cat /sys/kernel/debug/cma/cma-vpu/count   # total pages
cat /sys/kernel/debug/cma/cma-vpu/used    # used pages
# used_bytes = used_pages * 4096
```

### CMA Pressure Symptoms

- `dma_alloc_coherent` returns NULL → CMA region exhausted
- V4L2 `VIDIOC_REQBUFS` fails with ENOMEM → ISP CMA full
- TFLite inference fails with "Failed to allocate tensor" → NPU CMA full
- GStreamer pipeline fails at `imxvpudec` → VPU CMA full

**Mitigation:** Kill unused processes holding CMA buffers, or increase CMA size in device
tree `reserved-memory` node and reboot.

---

## DMA-BUF (Direct Memory Access Buffer Sharing)

DMA-BUF is the Linux kernel framework for zero-copy buffer sharing between hardware
subsystems. On i.MX 95, it is used extensively:

```
Camera sensor → ISP → DMA-BUF → VPU encoder → DMA-BUF → NPU inference
                              ↘ DMA-BUF → Display (DRM/KMS)
```

### Key Properties

- DMA-BUF buffers are allocated from CMA (for hardware DMA) or from system memory
  (for CPU-only access).
- A single DMA-BUF can be mapped by multiple processes simultaneously (zero-copy sharing).
- The buffer's memory is not freed until **all** file descriptors referencing it are closed.
- DMA-BUF memory does **not** appear in a process's `VmRSS` — it is tracked separately.

### Reading DMA-BUF State

```bash
# Requires debugfs + CONFIG_DMA_BUF_SYSFS_STATS=y
cat /sys/kernel/debug/dma_buf/bufinfo

# Per-process DMA-BUF fds (requires root)
for pid in /proc/[0-9]*/; do
    comm=$(cat "${pid}comm" 2>/dev/null)
    count=$(grep -l "^dmabuf" "${pid}fdinfo/"* 2>/dev/null | wc -l)
    [ "${count}" -gt 0 ] && echo "${comm}: ${count} DMA-BUF fds"
done
```

---

## Memory Accounting: What Goes Where

Understanding why `MemFree` ≠ `MemAvailable` ≠ actual usable memory:

```
MemTotal
  └── MemFree          (truly free pages — kernel won't use without asking)
  └── Buffers          (kernel I/O buffers — reclaimable)
  └── Cached           (page cache — reclaimable under pressure)
  └── AnonPages        (process heap/stack — not reclaimable without swap)
  └── Mapped           (mmap'd files — partially reclaimable)
  └── Shmem            (shared memory / tmpfs)
  └── KernelStack      (kernel thread stacks)
  └── PageTables       (page table entries)
  └── Slab             (kernel object caches — partially reclaimable)
  └── CmaTotal         (CMA reserved — NOT in MemFree or MemAvailable)

MemAvailable ≈ MemFree + reclaimable(Buffers + Cached + Slab)
             — this is what the kernel reports as "safe to allocate"
```

**Key insight:** CMA memory is subtracted from `MemTotal` at boot. A board with 4 GB RAM
and 512 MB CMA will show ~3.5 GB `MemTotal`. The CMA is not "wasted" — it is available
to CMA-capable allocators (DMA engines) but not to `malloc()`.

---

## LPDDR4/5 Specifics on i.MX 95

- **Bus width:** 32-bit or 64-bit depending on package
- **Typical speed:** LPDDR4 at 3200 MT/s, LPDDR5 at 6400 MT/s
- **ECC:** Optional; if enabled, reduces usable capacity by ~12.5%
- **Interleaving:** Memory controller supports bank/rank interleaving for bandwidth
- **Power states:** Self-refresh (SR) during idle; partial array self-refresh (PASR) for
  deeper power savings

### Bandwidth Considerations

The NPU, GPU, ISP, and VPU all compete for DRAM bandwidth. Typical peak bandwidth:
- LPDDR4-3200 (64-bit): ~25 GB/s theoretical, ~18 GB/s practical
- NPU alone can consume 8–12 GB/s during inference
- Running NPU + camera pipeline simultaneously may cause memory bandwidth saturation

Monitor with: `perf stat -e cache-misses,cache-references` or DDR performance counters
via `/sys/bus/platform/drivers/imx-ddr-perf/` (if driver loaded).

---

## Debugging Memory Issues

### OOM Kill Events

```bash
dmesg | grep -i "out of memory\|oom.kill\|killed process"
# Look for: "Out of memory: Kill process <pid> (<name>) score <N> or sacrifice child"
```

### Finding Memory Leaks

```bash
# Watch available memory over time
watch -n 1 'awk "/MemAvailable/{print \$2/1024 \" MB\"}" /proc/meminfo'

# Find processes with growing RSS
watch -n 2 'ps aux --sort=-%mem | head -15'
```

### CMA Fragmentation

CMA can become fragmented if small allocations are made from a large CMA region. Symptoms:
- `dma_alloc_coherent` fails for large buffers even though `CmaFree` shows enough space
- Fix: reboot (CMA is defragmented at boot), or use smaller allocation sizes

### DMA-BUF Leaks

If DMA-BUF memory grows over time without corresponding process RSS growth:
```bash
# Check total DMA-BUF memory
cat /sys/kernel/debug/dma_buf/bufinfo | grep "^size:" | awk '{sum+=$2} END{print sum/1024/1024 " MB"}'

# Find which exporter is leaking
cat /sys/kernel/debug/dma_buf/bufinfo | grep "exp_name:" | sort | uniq -c | sort -rn
```
