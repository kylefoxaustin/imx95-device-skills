---
name: imx95-memory-audit
version: "0.1.0"
platform: imx95
invoke_when:
  - "out of memory"
  - "allocation failed"
  - "CMA exhausted"
  - "how much memory is free"
  - "how much CMA is free"
  - "memory audit"
  - "check memory"
  - "DMA-BUF usage"
  - "what is using memory"
  - "top memory consumers"
  - "memory pressure"
  - "before loading a large model"
  - "V4L2 buffer allocation failed"
requires:
  - bash
  - awk
  - grep
  - cat
  - sort
safe: true
destructive: false
---

# Skill: imx95-memory-audit

## Purpose

Performs a detailed memory audit of the i.MX 95 board. Reports total/free/available RAM,
CMA allocation and usage per region, DMA-BUF heap state, top-10 processes by RSS, hugepage
state, vmalloc usage, and top slab consumers.

Use this skill:
- When the user reports "out of memory", "allocation failed", or "CMA exhausted"
- Before loading a large ML model or starting a camera pipeline
- When `imx95-diagnostic` flags low available memory
- Debugging DMA-BUF or V4L2 buffer allocation failures
- As part of `imx95-perf-investigator` (Step 4)

This skill is **read-only and safe**. It mounts debugfs if not already mounted
(benign and standard on Linux).

---

## Usage

```bash
# Full audit
bash skills/imx95-memory-audit/scripts/audit.sh

# Quick summary only
bash skills/imx95-memory-audit/scripts/audit.sh --summary

# CMA only
bash skills/imx95-memory-audit/scripts/audit.sh --section CMA

# Per-process RSS only
bash skills/imx95-memory-audit/scripts/audit.sh --section PROCESSES
```

---

## Step-by-Step Procedure

1. Run `scripts/audit.sh` (mounts debugfs automatically if needed).
2. Parse the `=== SECTION ===` output blocks.
3. Flag these conditions:
   - Available RAM < 256 MB → warn; < 128 MB → alert
   - CMA usage > 80% in any region → warn (VPU/ISP/NPU allocations may fail)
   - Any OOM kill events in dmesg → alert with process name
   - DMA-BUF total > 512 MB → note (large buffer pool)
   - Top RSS process > 512 MB → note
4. Report findings with specific numbers and identify the top memory consumer.

---

## Output Format

```
=== MEMINFO SUMMARY ===
Total RAM   : 3927 MB
Available   : 2841 MB  (28% used)
...

=== CMA REGIONS ===
cma-vpu     : 180 MB used / 256 MB total  (70%)
...

=== DMA-BUF ===
=== TOP PROCESSES BY RSS ===
=== HUGEPAGES ===
=== VMALLOC ===
=== SLAB TOP CONSUMERS ===
```

---

## Caveats

- DMA-BUF bufinfo requires debugfs mounted at `/sys/kernel/debug`. The script mounts it
  automatically if missing.
- Per-CMA-region stats (`/sys/kernel/debug/cma/`) require `CONFIG_CMA_DEBUGFS=y` in the
  kernel config. If not available, only `/proc/meminfo` CmaTotal/CmaFree are shown.
- `/proc/*/status` scanning requires read access to all process directories. Run as root
  for complete per-process data.
- Slab info from `/proc/slabinfo` requires root on most kernels.
