# CLAUDE.md — imx95-device-skills

> **Primary ingestion document for Claude Code.**
> Read this file completely before executing any command on the board.
> Every section is actionable. Do not skip Safety Rules or Platform Gotchas.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [How Skills Work](#3-how-skills-work)
4. [Directory Layout](#4-directory-layout)
5. [Bootstrap & Install](#5-bootstrap--install)
6. [Quick Start](#6-quick-start)
7. [Skills Reference](#7-skills-reference)
   - [imx95-diagnostic](#71-imx95-diagnostic)
   - [imx95-print-device-info](#72-imx95-print-device-info)
   - [imx95-memory-audit](#73-imx95-memory-audit)
   - [imx95-npu-benchmark](#74-imx95-npu-benchmark)
   - [imx95-npu-serve](#75-imx95-npu-serve)
   - [imx95-camera-setup](#76-imx95-camera-setup)
   - [imx95-gpio-config](#77-imx95-gpio-config)
   - [imx95-headless-mode](#78-imx95-headless-mode)
   - [imx95-package](#79-imx95-package)
   - [imx95-perf-investigator](#710-imx95-perf-investigator)
8. [Safety Rules](#8-safety-rules)
9. [Platform-Specific Gotchas](#9-platform-specific-gotchas)
10. [Running Evals](#10-running-evals)
11. [Adding a New Skill](#11-adding-a-new-skill)
12. [Sysfs Quick Reference](#12-sysfs-quick-reference)

---

## 1. Project Overview

**imx95-device-skills** is an [AgentSkills.io](https://agentskills.io)-convention repository that
turns Claude Code into an on-board AI assistant for the **NXP FRDM-IMX95 EVK** and compatible
i.MX 95 custom boards. Unlike host-side tooling repos, this repo is cloned *directly onto the
board* (or onto a host that has SSH access to the board). Claude Code connects via SSH and
executes skills — small, self-contained scripts with structured metadata — to configure,
diagnose, benchmark, and operate the board without requiring the user to remember dozens of
sysfs paths, GStreamer pipelines, or eIQ CLI flags.

Each skill is a focused capability unit: a `SKILL.md` that describes intent and usage, one or
more scripts under `scripts/`, optional evaluation harnesses under `evals/`, and reference
material under `references/`. Claude Code reads `SKILL.md` first, then decides which script to
run, what arguments to pass, and how to interpret the output. Skills are composable — the
`imx95-perf-investigator` skill, for example, orchestrates several other skills in sequence to
diagnose a performance complaint end-to-end.

This repo is intentionally **board-native**: it assumes a Yocto-based NXP BSP image (meta-imx,
kernel 6.6.x LTS) running on the i.MX 95 SoC. It does **not** use NVIDIA-specific tools
(no `tegrastats`, no `nvpmodel`, no CUDA). All power, thermal, and frequency data come from
Linux sysfs. All NPU operations go through the eIQ Toolkit (TFLite delegate or ONNX Runtime
with eIQ backend). If you are porting skills to a different i.MX SoC, read
[Platform-Specific Gotchas](#9-platform-specific-gotchas) first.

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Developer Workstation (Host)                  │
│                                                                      │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │  Claude Code  (claude CLI or IDE extension)                   │  │
│   │                                                               │  │
│   │   reads CLAUDE.md ──► selects skill ──► reads SKILL.md       │  │
│   │         │                                                     │  │
│   │         └──── SSH ──────────────────────────────────────┐    │  │
│   └─────────────────────────────────────────────────────────│────┘  │
│                                                             │        │
└─────────────────────────────────────────────────────────────│────────┘
                                                              │ SSH / SCP
                                                              │
┌─────────────────────────────────────────────────────────────▼────────┐
│                    FRDM-IMX95 EVK  (Target Board)                     │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │  /opt/imx95-device-skills/                                       │ │
│  │                                                                   │ │
│  │  skills/                                                          │ │
│  │  ├── imx95-diagnostic/      ◄── SKILL.md + scripts/              │ │
│  │  ├── imx95-print-device-info/                                     │ │
│  │  ├── imx95-memory-audit/                                          │ │
│  │  ├── imx95-npu-benchmark/                                         │ │
│  │  ├── imx95-npu-serve/                                             │ │
│  │  ├── imx95-camera-setup/                                          │ │
│  │  ├── imx95-gpio-config/                                           │ │
│  │  ├── imx95-headless-mode/                                         │ │
│  │  ├── imx95-package/                                               │ │
│  │  └── imx95-perf-investigator/                                     │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  SoC: i.MX 95                                                         │
│  ├── 6× Cortex-A55 @ 1.8 GHz  (cpufreq / schedutil)                 │
│  ├── 1× Cortex-M7  @ 800 MHz  (remoteproc / RPMsg)                  │
│  ├── 1× Cortex-M33            (remoteproc / RPMsg)                  │
│  ├── NPU: eIQ Neutron ~4 TOPS (TFLite delegate / ONNX-eIQ)          │
│  ├── GPU: Vivante GC7000UL    (DRM/KMS, OpenCL, Vulkan)             │
│  ├── 2× MIPI-CSI              (V4L2 / GStreamer)                     │
│  ├── PCIe Gen3, USB 3.0, GbE                                         │
│  └── LPDDR4/5                                                        │
└───────────────────────────────────────────────────────────────────────┘
```

**Connection model:** Claude Code runs on the host. It SSHes into the board, reads skill
scripts, and executes them remotely. All file paths in skill scripts are *board-side absolute
paths* (e.g., `/opt/imx95-device-skills/skills/...`). Claude Code never assumes it is running
locally unless `hostname` confirms it is on the board.

---

## 3. How Skills Work

### The AgentSkills Convention

Every skill is a self-contained directory with a fixed layout:

```
skills/<skill-name>/
├── SKILL.md          # Machine-readable + human-readable skill spec (READ FIRST)
├── scripts/          # Executable scripts Claude runs on the board
│   ├── main.sh       # Primary entry point (always present)
│   └── *.sh / *.py   # Supporting scripts
├── evals/            # Evaluation harnesses
│   ├── eval.sh       # Runs the skill and checks output
│   └── expected/     # Golden output fragments for assertion
└── references/       # Static reference material (sysfs paths, model zoo URLs, etc.)
    └── *.md
```

### SKILL.md Structure

Each `SKILL.md` begins with a YAML front-matter block:

```yaml
---
name: imx95-<skill-name>
version: 1.0.0
description: One-line description
invoke_when:
  - Trigger phrase 1
  - Trigger phrase 2
requires:
  - tool-or-package-1
  - tool-or-package-2
safe: true          # false = requires explicit user confirmation before running
destructive: false  # true = modifies persistent state (flash, eMMC, fuses)
---
```

Followed by:
- **Purpose** — what the skill does and why
- **Usage** — how Claude should call `scripts/main.sh` and what arguments it accepts
- **Output format** — what stdout/stderr looks like so Claude can parse it
- **Interpretation guide** — how to turn raw output into actionable advice
- **Caveats** — edge cases, known failures, board-specific quirks

### Execution Protocol

Claude Code **must** follow this sequence for every skill invocation:

1. **Read `SKILL.md`** completely before running any script.
2. **Check `safe:` and `destructive:` flags.** If `destructive: true`, present a summary of
   what will change and wait for explicit user confirmation (`yes/no`) before proceeding.
3. **Verify prerequisites** listed in `requires:` are present on the board
   (`which <tool>` or `ls <path>`).
4. **Run `scripts/main.sh`** (or the script specified in SKILL.md) via SSH.
5. **Parse and summarize output** per the skill's interpretation guide.
6. **Report findings** in plain language with specific values, not just raw output dumps.

### Skill Composition

Skills may call other skills. When `SKILL.md` lists a `depends_on:` field, Claude must run
those dependency skills first and pass their output as context. The
`imx95-perf-investigator` skill is the primary example of a composed, multi-skill workflow.

---

## 4. Directory Layout

```
imx95-device-skills/
│
├── CLAUDE.md                          ← YOU ARE HERE (primary ingestion doc)
├── README.md                          ← Human-facing project overview
├── install.sh                         ← Bootstrap script (run once on board)
├── .agentskills.json                  ← Repo manifest (name, version, platform)
│
├── skills/
│   │
│   ├── imx95-diagnostic/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh                ← Full board snapshot
│   │   │   ├── cpu_info.sh
│   │   │   ├── thermal_info.sh
│   │   │   ├── peripheral_scan.sh
│   │   │   └── kernel_info.sh
│   │   ├── evals/
│   │   │   ├── eval.sh
│   │   │   └── expected/
│   │   │       └── sections.txt       ← Required section headers in output
│   │   └── references/
│   │       └── sysfs_paths.md
│   │
│   ├── imx95-print-device-info/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   └── main.sh                ← One-liner board identity
│   │   └── evals/
│   │       └── eval.sh
│   │
│   ├── imx95-memory-audit/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── cma_audit.sh
│   │   │   ├── dmabuf_audit.sh
│   │   │   └── per_process_rss.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── memory_layout.md
│   │
│   ├── imx95-npu-benchmark/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── run_tflite_benchmark.sh
│   │   │   ├── run_onnx_benchmark.sh
│   │   │   └── parse_results.py
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       ├── model_zoo.md
│   │       └── expected_tops.md
│   │
│   ├── imx95-npu-serve/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── serve_tflite.sh
│   │   │   ├── serve_onnx.sh
│   │   │   └── health_check.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── eiq_runtime_notes.md
│   │
│   ├── imx95-camera-setup/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── detect_cameras.sh
│   │   │   ├── test_capture.sh
│   │   │   └── gst_pipeline.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── mipi_csi_notes.md
│   │
│   ├── imx95-gpio-config/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── list_gpios.sh
│   │   │   ├── read_gpio.sh
│   │   │   └── write_gpio.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── gpio_banks.md
│   │
│   ├── imx95-headless-mode/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── disable_display.sh
│   │   │   ├── enable_display.sh
│   │   │   └── check_display_state.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── drm_kms_notes.md
│   │
│   ├── imx95-package/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── main.sh
│   │   │   ├── detect_pkg_manager.sh
│   │   │   ├── install_pkg.sh
│   │   │   └── remove_pkg.sh
│   │   ├── evals/
│   │   │   └── eval.sh
│   │   └── references/
│   │       └── yocto_package_notes.md
│   │
│   └── imx95-perf-investigator/
│       ├── SKILL.md
│       ├── scripts/
│       │   ├── main.sh                ← Orchestrator
│       │   ├── collect_baseline.sh
│       │   ├── stress_test.sh
│       │   ├── analyze_bottleneck.sh
│       │   └── report.py
│       ├── evals/
│       │   └── eval.sh
│       └── references/
│           └── perf_tuning_guide.md
│
├── evals/
│   ├── run_all_evals.sh               ← Run every skill's eval suite
│   └── report_template.md
│
├── lib/
│   ├── common.sh                      ← Shared shell helpers (logging, assert, etc.)
│   ├── sysfs.sh                       ← Sysfs read helpers with fallback paths
│   └── board_detect.sh                ← Detect board variant at runtime
│
└── docs/
    ├── adding-a-skill.md
    ├── sysfs-reference.md
    └── eiq-inference-guide.md
```

---

## 5. Bootstrap & Install

### Prerequisites (on the board)

- Yocto NXP BSP image with `meta-imx` layers, kernel 6.6.x LTS
- `bash`, `python3`, `git` available
- Network access (Ethernet or Wi-Fi) for package installs
- SSH server running (`sshd`)

### One-Time Install

Run this **on the board** (or pipe it over SSH from the host):

```bash
# On the board as root or a sudoer:
git clone https://github.com/your-org/imx95-device-skills.git /opt/imx95-device-skills
cd /opt/imx95-device-skills
bash install.sh
```

`install.sh` does the following (non-destructive, idempotent):

```
1. Verifies the board is i.MX 95 (reads /sys/firmware/devicetree/base/compatible)
2. Checks kernel version >= 6.6
3. Installs missing host tools: python3-pip, libgpiod-tools, v4l-utils, gstreamer1.0-tools
4. Installs Python deps: tflite-runtime, onnxruntime (eIQ wheel if available)
5. Creates /usr/local/bin/imx95-skill symlink → lib/skill_runner.sh
6. Adds /opt/imx95-device-skills/skills to PATH in /etc/profile.d/imx95-skills.sh
7. Runs a smoke test: imx95-print-device-info
```

### Connecting Claude Code (Host Side)

```bash
# In your project directory on the host:
claude --ssh root@<board-ip> --repo /opt/imx95-device-skills
```

Claude Code will automatically read `CLAUDE.md` on first connection. No further setup needed.

### Updating Skills

```bash
# On the board:
cd /opt/imx95-device-skills && git pull
# Or from the host:
ssh root@<board-ip> "cd /opt/imx95-device-skills && git pull"
```

---

## 6. Quick Start

**Scenario:** You just connected Claude Code to a fresh FRDM-IMX95 EVK and want to understand
what you're working with.

**Step 1 — Claude Code reads this file.** It now knows the platform, all available skills, and
the safety rules.

**Step 2 — Type your first prompt:**

```
What's running on this board?
```

**What Claude does:**

1. Recognizes this as a board identity + status query.
2. Selects `imx95-print-device-info` for a quick one-liner, then `imx95-diagnostic` for depth.
3. SSHes to the board, reads each skill's `SKILL.md`.
4. Runs `skills/imx95-print-device-info/scripts/main.sh` → prints SoC rev, kernel, uptime.
5. Asks: *"Want a full diagnostic snapshot? It takes ~15 seconds."*
6. On confirmation, runs `skills/imx95-diagnostic/scripts/main.sh`.
7. Returns a structured summary: CPU topology, memory, thermals, active peripherals, any
   anomalies (throttling, OOM events, failed services).

**Other first prompts that work immediately:**

| Prompt | Skill invoked |
|--------|---------------|
| `"Run an NPU benchmark"` | `imx95-npu-benchmark` |
| `"Is my MIPI camera detected?"` | `imx95-camera-setup` |
| `"Show me all GPIO lines"` | `imx95-gpio-config` |
| `"The board feels slow, investigate"` | `imx95-perf-investigator` |
| `"Install python3-numpy"` | `imx95-package` |
| `"How much CMA memory is free?"` | `imx95-memory-audit` |
| `"Set the board to headless mode"` | `imx95-headless-mode` (confirms first) |

---

## 7. Skills Reference

### 7.1 `imx95-diagnostic`

**Purpose:** Full board snapshot — CPU, memory, thermal, power, kernel, and peripherals in one
structured report.

**Invoke when:**
- User asks "what's the state of the board", "run diagnostics", "something is wrong"
- Before starting any benchmark or workload (baseline capture)
- After a crash, reboot, or unexpected behavior
- As the first step in `imx95-perf-investigator`

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Orchestrates all sub-scripts, formats final report |
| `scripts/cpu_info.sh` | CPU topology, current/min/max frequencies, governor, online cores |
| `scripts/thermal_info.sh` | All thermal zones, trip points, current temps, throttle events |
| `scripts/peripheral_scan.sh` | USB, PCIe, I2C buses, V4L2 devices, remoteproc state |
| `scripts/kernel_info.sh` | Kernel version, cmdline, dmesg errors/warnings (last 50 lines) |

**Key sysfs paths used:**

```
/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq
/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
/sys/class/thermal/thermal_zone*/temp
/sys/class/thermal/thermal_zone*/type
/sys/class/thermal/thermal_zone*/trip_point_*_temp
/sys/bus/remoteproc/devices/remoteproc*/state
/proc/meminfo
/proc/cpuinfo
```

**Output format:** Structured sections separated by `=== SECTION ===` headers. Claude parses
each section independently and flags values outside normal ranges (e.g., CPU temp > 85°C,
throttle events > 0, any `[ERROR]` in dmesg).

**Safe:** Yes. Read-only. No side effects.

---

### 7.2 `imx95-print-device-info`

**Purpose:** Quick one-liner board identity — SoC revision, board revision, kernel version,
uptime, and hostname. Completes in under 2 seconds.

**Invoke when:**
- User asks "what board is this", "what kernel is running", "quick board info"
- At the start of any session as a sanity check
- When logging results (prepend to any benchmark output)

**Key script:** `scripts/main.sh`

```bash
# What main.sh prints (example output):
# BOARD: FRDM-IMX95 | SOC: i.MX95 rev1.1 | KERNEL: 6.6.23-lts-next+g... | UPTIME: 2h14m | HOST: imx95-evk
```

**How it works:**

```bash
# SoC identity
cat /sys/firmware/devicetree/base/compatible          # e.g., fsl,imx95-19x19-evk
cat /sys/firmware/devicetree/base/model               # e.g., NXP i.MX95 19x19 EVK board

# SoC revision
cat /sys/devices/soc0/soc_id                          # e.g., i.MX95
cat /sys/devices/soc0/revision                        # e.g., 1.1

# Kernel
uname -r

# Uptime
cat /proc/uptime | awk '{printf "%dh%dm\n", $1/3600, ($1%3600)/60}'
```

**Safe:** Yes. Read-only.

---

### 7.3 `imx95-memory-audit`

**Purpose:** Detailed memory breakdown — total/free/available RAM, CMA allocation and usage,
DMA-BUF heap state, per-process RSS top-10, and any OOM events in dmesg.

**Invoke when:**
- User reports "out of memory", "allocation failed", "CMA exhausted"
- Before loading a large model or starting a camera pipeline
- When `imx95-diagnostic` flags low available memory
- Debugging DMA-BUF or V4L2 buffer allocation failures

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Aggregates all memory sub-reports |
| `scripts/cma_audit.sh` | CMA total, used, free from debugfs |
| `scripts/dmabuf_audit.sh` | DMA-BUF heap sizes, per-fd usage via `/proc/*/fdinfo` |
| `scripts/per_process_rss.sh` | Top-10 processes by RSS from `/proc/*/status` |

**Key paths:**

```
/proc/meminfo                                    # MemTotal, MemFree, MemAvailable, CmaTotal, CmaFree
/sys/kernel/debug/cma/*/used                     # Per-CMA-region usage (requires debugfs mounted)
/sys/kernel/debug/dma_buf/bufinfo                # DMA-BUF buffer inventory
/proc/*/status                                   # VmRSS per process
/proc/*/fdinfo/*                                 # DMA-BUF fd details
```

**Prerequisite:** debugfs must be mounted:

```bash
mount -t debugfs none /sys/kernel/debug   # if not already mounted
```

`main.sh` checks and mounts automatically if missing (non-destructive).

**Safe:** Yes. Read-only (mount of debugfs is benign and standard).

---

### 7.4 `imx95-npu-benchmark`

**Purpose:** Run a standardized inference benchmark on the i.MX 95 NPU (eIQ Neutron), report
latency (ms), throughput (inferences/sec), and effective TOPS. Supports TFLite delegate and
ONNX Runtime with eIQ backend.

**Invoke when:**
- User asks "how fast is the NPU", "benchmark the NPU", "what TOPS can I get"
- Validating NPU functionality after BSP update
- Comparing model performance before/after optimization
- As part of `imx95-perf-investigator` when NPU workloads are involved

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Selects backend, runs benchmark, calls `parse_results.py` |
| `scripts/run_tflite_benchmark.sh` | Runs `benchmark_model` with NPU delegate |
| `scripts/run_onnx_benchmark.sh` | Runs ONNX Runtime with eIQ execution provider |
| `scripts/parse_results.py` | Parses raw output → structured JSON with TOPS estimate |

**Usage:**

```bash
# Default: MobileNetV2 on TFLite NPU delegate, 50 runs
scripts/main.sh

# Custom model
scripts/main.sh --model /path/to/model.tflite --backend tflite --runs 100

# ONNX backend
scripts/main.sh --model /path/to/model.onnx --backend onnx
```

**How TFLite benchmark runs:**

```bash
benchmark_model \
  --graph=/path/to/model.tflite \
  --use_nnapi=false \
  --external_delegate_path=/usr/lib/libethosu_delegate.so \
  --num_runs=50 \
  --warmup_runs=5 \
  --min_secs=0
```

> **Note:** The eIQ Neutron NPU delegate library path may vary by BSP version. `main.sh`
> searches common locations: `/usr/lib/libethosu_delegate.so`,
> `/usr/lib/libvx_delegate.so`, `/usr/local/lib/libethosu_delegate.so`.
> If none found, it falls back to CPU and warns the user.

**TOPS calculation:**

```
TOPS = (2 × MAC_ops_per_inference × inferences_per_second) / 1e12
```

`parse_results.py` reads MAC count from the model's metadata if available, otherwise uses
a known-model lookup table in `references/expected_tops.md`.

**Expected NPU performance (reference):**

| Model | Precision | Expected latency | Expected TOPS |
|-------|-----------|-----------------|---------------|
| MobileNetV2 | INT8 | ~2–4 ms | ~1.5–2.5 |
| ResNet-50 | INT8 | ~8–15 ms | ~2.5–3.5 |
| YOLOv5s | INT8 | ~15–30 ms | ~2.0–3.0 |

**Safe:** Yes. Does not modify any persistent state. CPU/NPU load is temporary.

---

### 7.5 `imx95-npu-serve`

**Purpose:** Serve a TFLite or ONNX model as an inference endpoint on the board, accessible
over HTTP. Uses a lightweight Python server wrapping the eIQ runtime. Optionally integrates
with llama.cpp for LLM-class models if the model fits in LPDDR5.

**Invoke when:**
- User wants to run inference from another machine or process
- Setting up a demo pipeline (camera → NPU → result stream)
- User asks "serve this model", "start inference server", "expose NPU over HTTP"

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Validates model, selects backend, starts server |
| `scripts/serve_tflite.sh` | Launches Python HTTP server with TFLite delegate |
| `scripts/serve_onnx.sh` | Launches Python HTTP server with ONNX-eIQ backend |
| `scripts/health_check.sh` | Polls `localhost:<port>/health` until ready or timeout |

**Usage:**

```bash
scripts/main.sh --model /path/to/model.tflite --port 8080
scripts/main.sh --model /path/to/model.onnx   --port 8080 --backend onnx
```

**API (once running):**

```
POST /infer          Content-Type: application/octet-stream  → raw tensor bytes
GET  /health         → {"status":"ok","backend":"tflite","model":"..."}
GET  /info           → model input/output shapes, delegate info
```

**Important:** This skill starts a **background process**. Claude must:
1. Record the PID returned by `main.sh` to stdout.
2. Offer to stop the server when the user is done (`kill <PID>`).
3. Never start a second server on the same port without stopping the first.

**Safe:** Yes, but starts a persistent background process. Claude will confirm port and model
path before starting. Stopping the server is always offered.

---

### 7.6 `imx95-camera-setup`

**Purpose:** Detect MIPI-CSI cameras connected to the board, identify sensor drivers, test a
capture pipeline with GStreamer, and save a test frame to disk.

**Invoke when:**
- User asks "is my camera working", "detect camera", "test MIPI CSI"
- Setting up a vision pipeline for the first time
- After a BSP update that may have changed V4L2 device numbering
- Debugging blank frames or pipeline errors

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Full detect → configure → test pipeline |
| `scripts/detect_cameras.sh` | Lists V4L2 devices, reads sensor name from sysfs |
| `scripts/test_capture.sh` | Captures one frame via `v4l2-ctl --stream-mmap` |
| `scripts/gst_pipeline.sh` | Builds and runs a GStreamer test pipeline |

**Detection approach:**

```bash
# List V4L2 devices
v4l2-ctl --list-devices

# Query sensor info
v4l2-ctl -d /dev/video0 --info
v4l2-ctl -d /dev/video0 --list-formats-ext

# Check I2C for known sensor addresses
i2cdetect -y 4    # CSI0 I2C bus (board-dependent, check DTS)
i2cdetect -y 5    # CSI1 I2C bus
```

**GStreamer test pipeline (example for OV5640):**

```bash
gst-launch-1.0 v4l2src device=/dev/video0 num-buffers=1 \
  ! video/x-raw,width=1920,height=1080,framerate=30/1 \
  ! jpegenc \
  ! filesink location=/tmp/test_frame.jpg
```

**Known sensors supported by NXP BSP:** OV5640, OV13858, OV2775, IMX219, IMX477.
`detect_cameras.sh` checks `references/mipi_csi_notes.md` for the sensor-to-driver mapping.

**Safe:** Yes. Capture test writes only to `/tmp/`. Does not modify device tree or kernel
parameters.

---

### 7.7 `imx95-gpio-config`

**Purpose:** List all GPIO chips and lines on the board, read the current state of a specific
line, and write a value to an output line — all via `libgpiod` (`gpioinfo`, `gpioget`,
`gpioset`).

**Invoke when:**
- User asks "show me the GPIOs", "what state is GPIO X", "set GPIO Y high"
- Debugging a peripheral that is controlled by GPIO (reset, enable, IRQ)
- Verifying GPIO assignments match the device tree

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Default: runs `list_gpios.sh` |
| `scripts/list_gpios.sh` | `gpioinfo` on all chips, formatted table |
| `scripts/read_gpio.sh` | `gpioget <chip> <line>` with chip/line validation |
| `scripts/write_gpio.sh` | `gpioset <chip> <line>=<value>` — **requires confirmation** |

**Usage:**

```bash
# List all GPIO lines
scripts/main.sh

# Read a specific line
scripts/read_gpio.sh --chip gpiochip4 --line 3

# Write a line (Claude will confirm before executing)
scripts/write_gpio.sh --chip gpiochip4 --line 3 --value 1
```

**i.MX 95 GPIO banks (FRDM-IMX95 EVK):**

| gpiochip | Controller | Lines | Notes |
|----------|-----------|-------|-------|
| gpiochip0 | GPIO1 | 32 | Low-power domain |
| gpiochip1 | GPIO2 | 32 | |
| gpiochip2 | GPIO3 | 32 | |
| gpiochip3 | GPIO4 | 32 | |
| gpiochip4 | GPIO5 | 32 | |
| gpiochip5 | PCAL6524 (I2C expander) | 24 | M.2 slot control |

> **Warning:** Writing to GPIO lines that control power rails, reset signals, or boot
> configuration can hang or brick the board. `write_gpio.sh` checks
> `references/gpio_banks.md` for a blocklist of protected lines and refuses to write them.

**Safe for reads:** Yes. **Writes require explicit user confirmation** (`safe: false` in
SKILL.md for write operations).

---

### 7.8 `imx95-headless-mode`

**Purpose:** Enable or disable the display output on the board. In headless mode, the DRM/KMS
display pipeline is disabled, freeing GPU memory and reducing power draw. Useful for
server-style deployments or when no monitor is connected.

**Invoke when:**
- User asks "disable the display", "run headless", "no monitor mode"
- Deploying the board as an edge inference node without a screen
- Reducing power consumption for battery-powered setups
- Re-enabling display after headless deployment

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Checks current state, routes to enable/disable |
| `scripts/check_display_state.sh` | Reports current DRM connector and CRTC state |
| `scripts/disable_display.sh` | Disables display via DRM, stops display-related services |
| `scripts/enable_display.sh` | Re-enables display, restarts Weston/Wayland if applicable |

**How headless disable works:**

```bash
# Check current state
cat /sys/class/drm/card0-HDMI-A-1/status      # connected / disconnected
cat /sys/class/drm/card0-HDMI-A-1/enabled     # enabled / disabled

# Disable via DRM (non-persistent, survives until reboot)
echo off > /sys/class/drm/card0-HDMI-A-1/status

# Stop Weston compositor if running
systemctl stop weston.service 2>/dev/null || true

# For persistent headless (across reboots), modify kernel cmdline:
# Add: video=HDMI-A-1:d  to bootargs in /etc/fw_env.config + fw_setenv
```

> **Persistent headless requires modifying U-Boot environment.** This is a `destructive`
> operation. Claude will present the exact `fw_setenv` command and wait for explicit
> confirmation before executing. See Safety Rules §8.

**Safe for check/non-persistent disable:** Yes.
**Persistent (fw_setenv) change:** `destructive: true` — requires confirmation.

---

### 7.9 `imx95-package`

**Purpose:** Install or remove software packages on the board, automatically detecting whether
the image uses `apt` (Debian-based Yocto variant) or `opkg` (standard Yocto/OpenEmbedded).

**Invoke when:**
- User asks "install X", "remove Y", "is package Z available"
- A skill's prerequisite check fails because a tool is missing
- User wants to add Python packages (`pip3 install`)

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Routes to correct package manager |
| `scripts/detect_pkg_manager.sh` | Detects `apt`, `opkg`, or `dnf`; sets `PKG_MGR` |
| `scripts/install_pkg.sh` | Installs package, verifies success |
| `scripts/remove_pkg.sh` | Removes package with confirmation |

**Detection logic:**

```bash
if command -v apt-get &>/dev/null; then   PKG_MGR=apt
elif command -v opkg &>/dev/null; then    PKG_MGR=opkg
elif command -v dnf &>/dev/null; then     PKG_MGR=dnf
else echo "ERROR: No supported package manager found"; exit 1
fi
```

**Usage:**

```bash
scripts/main.sh --action install --package libgpiod-tools
scripts/main.sh --action remove  --package libgpiod-tools
scripts/main.sh --action search  --package tflite
```

**Notes:**
- On Yocto `opkg` images, the package feed URL must be configured. `install_pkg.sh` checks
  `/etc/opkg/` for feed configuration and warns if feeds are not set up.
- `pip3 install` is handled separately: `scripts/main.sh --action pip --package numpy`
- Package removal always asks for confirmation regardless of `safe:` flag.

**Safe for search/install:** Yes (install is non-destructive to board firmware).
**Remove:** Requires confirmation.

---

### 7.10 `imx95-perf-investigator`

**Purpose:** End-to-end agent workflow for investigating a performance complaint. Collects
baseline metrics, identifies the bottleneck (CPU/memory/NPU/thermal/IO), runs targeted stress
tests, and produces a structured report with specific tuning recommendations.

**Invoke when:**
- User says "the board is slow", "inference is taking too long", "something is throttling"
- Latency regression after a BSP or model update
- Preparing a performance report for a workload

**This skill orchestrates other skills in sequence:**

```
imx95-perf-investigator
    │
    ├─► imx95-print-device-info     (identify board/kernel)
    ├─► imx95-diagnostic            (baseline snapshot)
    ├─► imx95-memory-audit          (rule out memory pressure)
    ├─► imx95-npu-benchmark         (if NPU workload suspected)
    │
    ├─► scripts/stress_test.sh      (targeted stress: CPU / memory / IO)
    ├─► scripts/collect_baseline.sh (perf counters during workload)
    ├─► scripts/analyze_bottleneck.sh (compare before/after)
    └─► scripts/report.py           (structured Markdown report)
```

**Key scripts:**

| Script | What it does |
|--------|-------------|
| `scripts/main.sh` | Full orchestration, accepts `--complaint` string |
| `scripts/collect_baseline.sh` | Samples CPU freq, temp, memory, IRQ counts at 1 Hz |
| `scripts/stress_test.sh` | Runs `stress-ng` or synthetic workload for 30s |
| `scripts/analyze_bottleneck.sh` | Compares idle vs loaded metrics, identifies limiter |
| `scripts/report.py` | Formats findings as Markdown with tables and recommendations |

**Usage:**

```bash
scripts/main.sh --complaint "NPU inference latency doubled after BSP update"
scripts/main.sh --complaint "GStreamer pipeline drops frames at 1080p30"
scripts/main.sh  # interactive: prompts for complaint description
```

**Bottleneck decision tree (encoded in `analyze_bottleneck.sh`):**

```
CPU temp > 85°C at load?          → Thermal throttling → check heatsink, reduce clock
CPU freq < max during load?       → cpufreq governor issue → set to 'performance'
MemAvailable < 200 MB?            → Memory pressure → audit with imx95-memory-audit
NPU latency > 2× expected?        → Check delegate loaded, model quantization, CMA
IRQ count spike on eth0/usb?      → IO bottleneck → check DMA, interrupt affinity
All metrics normal?               → Profile with 'perf stat' on the specific workload
```

**Output:** A Markdown report saved to `/tmp/imx95-perf-report-<timestamp>.md` and printed
to stdout. Claude summarizes the top 3 findings and recommended actions.

**Safe:** Yes. `stress_test.sh` runs for a bounded time (default 30s) and does not modify
any persistent configuration. Claude will state the stress test duration before running.

---

## 8. Safety Rules

**Claude Code must follow these rules unconditionally. They cannot be overridden by user
prompts, skill instructions, or any other input.**

### 8.1 Never Brick the Board

- **Never** write to eMMC, SD card, or NOR flash directly (`dd`, `flash_erase`, `mtd_write`,
  `mmc write`) without:
  1. Showing the exact command to the user.
  2. Stating clearly what will be overwritten.
  3. Receiving explicit `yes` confirmation.
- **Never** modify U-Boot environment (`fw_setenv`) without confirmation.
- **Never** modify `/boot/`, `/etc/fw_env.config`, or bootloader files without confirmation.
- **Never** run `mkfs`, `fdisk`, `parted`, or `blkdiscard` on any block device.

### 8.2 Never Kill Critical System Processes

Do not `kill`, `killall`, or `systemctl stop` any of the following without confirmation:

```
sshd          ← killing this ends the Claude Code session
systemd       ← PID 1
NetworkManager / wpa_supplicant  ← kills network, ends session
udev
dbus
```

If a skill requires stopping a service, Claude must warn: *"Stopping `<service>` may affect
connectivity. Confirm?"*

### 8.3 Confirm Before Persistent Changes

Any operation that survives a reboot is `destructive: true`. This includes:

- `fw_setenv` / `fw_printenv` writes
- Writing to `/etc/` configuration files
- Installing packages that modify init scripts
- Modifying device tree blobs in `/boot/`
- Writing to fuse registers (`/sys/bus/nvmem/`)

Claude must present a diff or summary of the change and wait for `yes` before proceeding.

### 8.4 Thermal Safety

- If any thermal zone reads **≥ 95°C**, immediately stop all benchmarks and workloads.
- Report the temperature and recommend the user check cooling before continuing.
- Do not run `imx95-npu-benchmark` or `imx95-perf-investigator` stress tests if the board
  is already above **80°C** at idle.

### 8.5 GPIO Write Safety

- Before writing any GPIO line, check `references/gpio_banks.md` for the protected-lines
  blocklist.
- Protected lines include: power-enable rails, eMMC reset, USB VBUS control, SoC reset.
- If the requested line is on the blocklist, refuse and explain why.

### 8.6 No Speculative Execution

- Do not run commands "to see what happens" on a production board.
- If unsure whether a command is safe, ask the user first.
- Prefer read-only sysfs queries over any write operation.

### 8.7 Preserve SSH Connectivity

- Always verify `sshd` is running before any network reconfiguration.
- If a skill modifies network interfaces, offer a rollback command before applying.
- Never change the IP address or hostname without confirmation.

---

## 9. Platform-Specific Gotchas

### 9.1 No tegrastats, No nvpmodel, No NVIDIA Tools

This is **not** a Jetson board. The following tools **do not exist** on i.MX 95:

```
tegrastats       → use sysfs thermal + cpufreq instead
nvpmodel         → use cpufreq governor + devfreq
nvmap            → use /sys/kernel/debug/dma_buf/bufinfo
nvidia-smi       → does not apply
jetson_clocks    → use scripts/set_max_clocks.sh (provided in lib/)
```

If you find yourself about to type any of these, stop and use the sysfs equivalents in
`lib/sysfs.sh`.

### 9.2 CPU Frequency — cpufreq, Not nvpmodel

All 6 Cortex-A55 cores share a single frequency domain on i.MX 95:

```bash
# Read current frequency (all cores share policy0)
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq   # in kHz

# Available frequencies
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies

# Set governor
echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor

# Set max frequency (requires root)
echo 1800000 > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
```

### 9.3 NPU — eIQ Neutron, Not CUDA/TensorRT

The NPU is the **eIQ Neutron** (~4 TOPS INT8). It is accessed via:

- **TFLite delegate:** `libethosu_delegate.so` or `libvx_delegate.so` (BSP-dependent)
- **ONNX Runtime:** eIQ execution provider (`--execution_provider=EiqExecutionProvider`)
- **eIQ Toolkit CLI:** `benchmark_model`, `eiq_run_model`

There is **no CUDA, no TensorRT, no cuDNN**. Do not suggest these.

The GPU (Vivante GC7000UL) is separate from the NPU and is used for display/OpenCL/Vulkan,
not for ML inference in the standard BSP.

### 9.4 Thermal Zones — Read All of Them

i.MX 95 exposes multiple thermal zones. Zone numbering varies by BSP version. Always iterate:

```bash
for zone in /sys/class/thermal/thermal_zone*/; do
    type=$(cat "$zone/type" 2>/dev/null)
    temp=$(cat "$zone/temp" 2>/dev/null)
    echo "$zone: $type = $((temp/1000))°C"
done
```

Do **not** hardcode `thermal_zone0` — it may not be the CPU zone on all BSP versions.

### 9.5 devfreq — GPU and DDR Frequency Scaling

```bash
# List devfreq devices
ls /sys/class/devfreq/

# DDR frequency
cat /sys/class/devfreq/*/cur_freq    # find the DDR entry by name

# GPU frequency (Vivante GC7000UL)
cat /sys/class/devfreq/*/cur_freq    # find the GPU entry
```

### 9.6 Remoteproc — M7 and M33 Cores

The Cortex-M7 and Cortex-M33 are managed via remoteproc:

```bash
# Check state
cat /sys/bus/remoteproc/devices/remoteproc0/state   # offline / running
cat /sys/bus/remoteproc/devices/remoteproc1/state

# Load firmware
echo /lib/firmware/imx/rproc/imx95-m7-rpmsg.elf > \
     /sys/bus/remoteproc/devices/remoteproc0/firmware
echo start > /sys/bus/remoteproc/devices/remoteproc0/state
```

Skills that interact with M7/M33 must check remoteproc state first.

### 9.7 V4L2 Device Numbering Is Not Stable

`/dev/video0` may not always be the MIPI-CSI camera. After a BSP update or USB camera
insertion, numbering can shift. Always use `v4l2-ctl --list-devices` and match by driver
name, not by device number.

### 9.8 debugfs Must Be Mounted

Several skills require debugfs:

```bash
mount | grep debugfs || mount -t debugfs none /sys/kernel/debug
```

This is safe and standard. Skills check and mount automatically.

### 9.9 eMMC vs SD Boot

The FRDM-IMX95 EVK can boot from eMMC or SD card. Before any flash operation:

```bash
# Identify boot device
cat /proc/cmdline | grep -o 'root=[^ ]*'
lsblk -o NAME,TYPE,MOUNTPOINT,SIZE
```

Never assume `/dev/mmcblk0` is the SD card — it may be eMMC.

### 9.10 Yocto Image Variants

NXP ships multiple Yocto image variants. Package availability differs:

| Image | Package manager | Notes |
|-------|----------------|-------|
| `imx-image-core` | opkg | Minimal, no apt |
| `imx-image-multimedia` | opkg | Adds GStreamer, V4L2 |
| `imx-image-full` | opkg | Adds eIQ, Qt, Weston |
| Custom Debian-based | apt | Some partners use this |

`imx95-package` detects the variant automatically. If `opkg` feeds are not configured,
it will warn and provide instructions to add the NXP package feed URL.

---

## 10. Running Evals

Each skill has an `evals/eval.sh` that validates the skill works correctly on the board.
The top-level `evals/run_all_evals.sh` runs all of them and produces a pass/fail report.

### Running All Evals

```bash
# On the board:
cd /opt/imx95-device-skills
bash evals/run_all_evals.sh

# From the host via SSH:
ssh root@<board-ip> "bash /opt/imx95-device-skills/evals/run_all_evals.sh"
```

### Running a Single Skill Eval

```bash
bash skills/imx95-diagnostic/evals/eval.sh
bash skills/imx95-npu-benchmark/evals/eval.sh
```

### Eval Output Format

```
[PASS] imx95-print-device-info: output contains SOC field
[PASS] imx95-diagnostic: all 6 sections present
[FAIL] imx95-npu-benchmark: delegate library not found at expected path
[SKIP] imx95-camera-setup: no V4L2 devices detected (no camera connected)
```

Exit code: `0` if all non-SKIP evals pass, `1` if any FAIL.

### What Evals Check

- **Output structure:** Required section headers or JSON keys are present.
- **Value ranges:** Temperatures are plausible (0–120°C), frequencies are non-zero.
- **No crashes:** Script exits 0, no Python tracebacks.
- **Idempotency:** Running twice produces consistent output.

Evals do **not** check absolute performance numbers (those vary by board revision and
thermal state). They check that the skill runs successfully and produces parseable output.

---

## 11. Adding a New Skill

Follow this checklist to add a skill to the repo:

### Step 1 — Create the directory structure

```bash
SKILL=imx95-my-new-skill
mkdir -p skills/$SKILL/{scripts,evals,references}
```

### Step 2 — Write `SKILL.md`

Copy the template from `docs/adding-a-skill.md`. Fill in all YAML front-matter fields.
The `invoke_when` list is critical — it determines when Claude selects this skill.

```yaml
---
name: imx95-my-new-skill
version: 1.0.0
description: One-line description of what this skill does
invoke_when:
  - "user asks about X"
  - "user wants to do Y"
  - "Z is failing or slow"
requires:
  - bash
  - python3
safe: true
destructive: false
---
```

### Step 3 — Write `scripts/main.sh`

```bash
#!/usr/bin/env bash
# imx95-my-new-skill/scripts/main.sh
set -euo pipefail

# Source shared helpers
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../.." && pwd)"
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/sysfs.sh"

# Your skill logic here
log_info "Starting imx95-my-new-skill"
```

### Step 4 — Write `evals/eval.sh`

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/../../lib/common.sh"

OUTPUT=$(bash "$(dirname "$0")/../scripts/main.sh" 2>&1)
assert_contains "$OUTPUT" "EXPECTED_STRING" "output contains expected string"
assert_exit_code 0 $? "main.sh exits cleanly"
```

### Step 5 — Update `CLAUDE.md`

Add a new subsection under [§7 Skills Reference](#7-skills-reference) following the exact
same format as existing skills (Purpose, Invoke when, Key scripts table, Usage, Safe flag).

### Step 6 — Update `.agentskills.json`

```json
{
  "skills": [
    "...",
    "imx95-my-new-skill"
  ]
}
```

### Step 7 — Test

```bash
bash skills/imx95-my-new-skill/evals/eval.sh
bash evals/run_all_evals.sh
```

### Step 8 — Submit PR

Branch naming: `feature/<your-name>/imx95-<skill-name>`
PR description must include: purpose, tested board/BSP version, eval output.

---

## 12. Sysfs Quick Reference

A condensed reference of the most-used sysfs paths on i.MX 95. Full details in
`docs/sysfs-reference.md`.

### CPU

```bash
/sys/devices/system/cpu/cpu*/online                          # core online state
/sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq     # current freq (kHz)
/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq     # max freq (kHz)
/sys/devices/system/cpu/cpufreq/policy0/scaling_governor     # governor name
/sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies
/sys/devices/system/cpu/cpufreq/policy0/stats/time_in_state  # time per freq
```

### Thermal

```bash
/sys/class/thermal/thermal_zone*/type                        # zone name
/sys/class/thermal/thermal_zone*/temp                        # millidegrees C
/sys/class/thermal/thermal_zone*/trip_point_*_temp           # trip thresholds
/sys/class/thermal/thermal_zone*/trip_point_*_type           # passive/active/critical
/sys/class/thermal/cooling_device*/cur_state                 # current cooling state
```

### Memory

```bash
/proc/meminfo                                                # MemTotal, MemFree, CmaTotal, CmaFree
/sys/kernel/debug/cma/*/used                                 # per-CMA-region usage
/sys/kernel/debug/dma_buf/bufinfo                            # DMA-BUF inventory
```

### GPU / devfreq

```bash
/sys/class/devfreq/*/name                                    # device name
/sys/class/devfreq/*/cur_freq                                # current freq (Hz)
/sys/class/devfreq/*/available_frequencies
/sys/class/devfreq/*/governor
```

### Board Identity

```bash
/sys/firmware/devicetree/base/compatible                     # board compatible string
/sys/firmware/devicetree/base/model                          # human-readable board name
/sys/devices/soc0/soc_id                                     # e.g., i.MX95
/sys/devices/soc0/revision                                   # e.g., 1.1
/sys/devices/soc0/machine                                    # machine name
```

### Remoteproc (M7 / M33)

```bash
/sys/bus/remoteproc/devices/remoteproc*/state                # offline/running/crashed
/sys/bus/remoteproc/devices/remoteproc*/firmware             # firmware path
/sys/bus/remoteproc/devices/remoteproc*/name                 # core name
```

### Display / DRM

```bash
/sys/class/drm/card0-HDMI-A-1/status                        # connected/disconnected
/sys/class/drm/card0-HDMI-A-1/enabled                       # enabled/disabled
/sys/class/drm/card0/                                        # DRM card directory
```

### Power / PMIC

```bash
/sys/class/power_supply/*/voltage_now                        # µV
/sys/class/power_supply/*/current_now                        # µA
/sys/class/power_supply/*/status                             # Charging/Discharging/Full
```

### U-Boot Environment

```bash
fw_printenv                                                  # read all U-Boot env vars
fw_printenv bootargs                                         # read kernel cmdline
fw_setenv <key> <value>                                      # write (DESTRUCTIVE — confirm first)
/etc/fw_env.config                                           # tells fw_printenv where env lives
```

---

*imx95-device-skills — AgentSkills.io convention — NXP FRDM-IMX95 EVK*
*Maintained by the NXP i.MX Software team. For issues, open a GitHub issue or contact the repo maintainers.*
