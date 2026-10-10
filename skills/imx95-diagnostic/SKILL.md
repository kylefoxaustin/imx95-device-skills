---
name: imx95-diagnostic
version: "0.1.0"
platform: imx95
invoke_when:
  - "run diagnostics"
  - "what is the state of the board"
  - "something is wrong"
  - "board health check"
  - "full board snapshot"
  - "check the board"
  - "board status"
  - "before starting a benchmark"
  - "after a crash or reboot"
  - "collect baseline"
  - "what is running on this board"
requires:
  - bash
  - uname
  - cat
  - awk
  - grep
  - lsmod
  - dmesg
  - df
  - ip
  - lsusb
  - lspci
safe: true
destructive: false
---

# Skill: imx95-diagnostic

## Purpose

Captures a comprehensive, structured snapshot of the FRDM-IMX95 EVK board state in a single
pass. Covers CPU topology and frequency scaling, memory, all thermal zones, GPU and NPU state,
storage, network interfaces, USB/PCIe peripherals, remoteproc (M7/M33) state, active systemd
services, and the last 20 kernel error messages.

Use this skill:
- As the **first step** in any investigation (establishes baseline)
- Before starting any benchmark or heavy workload
- After a crash, unexpected reboot, or anomalous behavior
- When the user asks "what's the state of the board" or "run diagnostics"
- As the first step in the `imx95-perf-investigator` agent

This skill is **read-only and safe** — it makes no changes to the board.

---

## Usage

```bash
# Full snapshot (default)
bash skills/imx95-diagnostic/scripts/snapshot.sh

# Verify this is an i.MX 95 board first
bash skills/imx95-diagnostic/scripts/detect_imx95.sh

# Quick board identity only
bash skills/imx95-print-device-info/scripts/print_info.sh
```

### Arguments for snapshot.sh

| Flag | Description |
|------|-------------|
| `--json` | Output structured JSON instead of human-readable text |
| `--section CPU` | Run only the CPU section |
| `--section THERMAL` | Run only the thermal section |
| `--section MEMORY` | Run only the memory section |
| `--no-dmesg` | Skip dmesg collection (faster, useful in CI) |
| `--quiet` | Suppress section headers; output values only |

---

## Step-by-Step Procedure

Claude follows this sequence when invoking this skill:

1. **Run `detect_imx95.sh`** — confirms the board is i.MX 95. If it exits non-zero, stop
   and report the error to the user.

2. **Run `snapshot.sh`** — collects all data. Typical runtime: 5–10 seconds.

3. **Parse each section** of the output (sections are delimited by `=== SECTION_NAME ===`).

4. **Flag anomalies** using these thresholds:
   - CPU temp > 75°C → warn; > 85°C → alert (throttling likely)
   - Any CPU at minimum frequency (300 MHz) under load → possible throttle or governor issue
   - Available memory < 256 MB → warn; < 128 MB → alert
   - CMA usage > 80% → warn
   - Any `[ERROR]` in dmesg → flag with message text
   - Any remoteproc in `crashed` state → alert
   - Any cooling device with `cur_state > 0` → note active thermal cooling

5. **Summarize findings** in plain language:
   - Lead with the most important finding (or "Board is healthy" if nothing anomalous)
   - List specific values (temperatures, frequencies, memory numbers)
   - Suggest next steps if anomalies are found

---

## Output Format

Output is structured text with section headers:

```
=== BOARD IDENTITY ===
Model     : NXP FRDM-IMX95-PRO
SoC       : i.MX95 rev1.1
Kernel    : 6.18.0 (this board — Yocto; NOT 6.6.x)
Uptime    : 2h 14m
Hostname  : imx95evk   ⚠️ NOT an identity — two fleet boards answer to it
Timestamp : 2024-01-15T10:30:00Z

=== CPU ===
cpu0: 1800 MHz  governor=schedutil  online=1
cpu1: 1800 MHz  governor=schedutil  online=1
...

=== THERMAL ===
cpu-thermal    : 52°C
soc-thermal    : 48°C
...

=== MEMORY ===
Total     : 3927 MB
Available : 2841 MB  (72% free)
CMA Total : 4.94 GiB   (960 MiB linux,cma + 4 GiB neutron_memory — the neutron DTB is booted)
CMA Free  : 480 MB  (94% free)
...

=== GPU ===
=== NPU ===
=== STORAGE ===
=== NETWORK ===
=== USB ===
=== PCIE ===
=== REMOTEPROC ===
=== SERVICES ===
=== DMESG ERRORS ===
```

---

## Interpretation Guide

| Section | What to look for | Threshold |
|---------|-----------------|-----------|
| CPU | Frequency under load | < 1000 MHz = possible throttle |
| CPU | Governor | `powersave` = performance limited |
| THERMAL | Any zone temp | > 75°C = warn, > 85°C = throttling |
| MEMORY | MemAvailable | < 256 MB = warn, < 128 MB = critical |
| MEMORY | CMA Free | < 20% = warn (affects VPU/ISP/NPU) |
| NPU | Driver state | `not_loaded` = NPU unavailable |
| REMOTEPROC | State | `crashed` = M7/M33 firmware failed |
| DMESG | Error count | Any errors = investigate |

---

## Caveats

- `lsusb` and `lspci` may not be installed on minimal Yocto images. The script handles
  missing tools gracefully and prints "tool not available" rather than failing.
- `dmesg` requires read access to kernel ring buffer. On some hardened images, non-root
  users may not have access. Run as root for full output.
- GPU devfreq node path varies by BSP version. The script searches multiple known paths.
- NPU driver name is `neutron` or `imx-neutron`. It is NEVER `ethosu` — that is the i.MX93 Ethos-U65. See references/imx95-ground-truth.md §1.1.
- Thermal zone numbering is not fixed — zone 0 may be CPU on one BSP and SoC on another.
  The script reads zone `type` files to label each zone correctly.
