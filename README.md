# imx95-device-skills

[![Platform](https://img.shields.io/badge/platform-i.MX%2095-blue)](https://www.nxp.com/products/processors-and-microcontrollers/arm-processors/i-mx-applications-processors/i-mx-9-processors/i-mx-95-applications-processor-family:iMX95)
[![Board](https://img.shields.io/badge/board-FRDM--IMX95%20EVK-green)](https://www.nxp.com/design/design-center/development-boards-and-designs/FRDM-IMX95)
[![AgentSkills](https://img.shields.io/badge/convention-AgentSkills.io-orange)](https://agentskills.io)
[![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)](LICENSE)
[![Kernel](https://img.shields.io/badge/kernel-6.6.x%20LTS-yellow)](https://kernel.org)

**imx95-device-skills** turns [Claude Code](https://claude.ai/code) into an on-board AI
assistant for the **NXP FRDM-IMX95 EVK** and compatible i.MX 95 custom boards. Clone this
repo directly onto the board (or onto a host with SSH access), run `install.sh`, and Claude
can diagnose, benchmark, configure, and operate the board using natural language.

> **Primary ingestion document for Claude Code:** [`CLAUDE.md`](CLAUDE.md)
> Read that file for the full architecture, safety rules, and skill reference.

---

## Quick Start

```bash
# 1. Clone onto the board (as root or sudoer)
git clone https://github.com/your-org/imx95-device-skills.git /opt/imx95-device-skills
cd /opt/imx95-device-skills

# 2. Install (idempotent — safe to re-run)
bash install.sh

# 3. Connect Claude Code from your host
claude --ssh root@<board-ip> --repo /opt/imx95-device-skills
```

Then just talk to Claude:

```
What's running on this board?
Run an NPU benchmark.
Is my MIPI camera detected?
The board feels slow — investigate.
How much CMA memory is free?
```

---

## Platform

| Property | Value |
|----------|-------|
| Board | NXP FRDM-IMX95 EVK |
| SoC | i.MX 95 |
| CPU | 6× Cortex-A55 @ 1.8 GHz |
| MCU | Cortex-M7 @ 800 MHz + Cortex-M33 |
| NPU | eIQ Neutron ~4 TOPS |
| GPU | Vivante GC7000UL |
| OS | Yocto Linux, kernel 6.6.x LTS |
| Memory | LPDDR4/5 |
| Storage | eMMC |

---

## Skills

| Skill | Description | Safe | Destructive |
|-------|-------------|------|-------------|
| [`imx95-diagnostic`](skills/imx95-diagnostic/SKILL.md) | Full board snapshot: CPU, memory, thermal, peripherals | ✅ | ❌ |
| [`imx95-print-device-info`](skills/imx95-print-device-info/SKILL.md) | Quick one-line board identity (SoC rev, kernel, uptime) | ✅ | ❌ |
| [`imx95-memory-audit`](skills/imx95-memory-audit/SKILL.md) | Detailed memory breakdown: CMA, DMA-BUF, per-process RSS | ✅ | ❌ |
| [`imx95-npu-benchmark`](skills/imx95-npu-benchmark/SKILL.md) | Run TFLite/ONNX inference benchmark on eIQ Neutron NPU | ✅ | ❌ |
| [`imx95-gpio-config`](skills/imx95-gpio-config/SKILL.md) | List, read, and write GPIO lines via libgpiod | ⚠️ | ❌ |
| [`imx95-headless-mode`](skills/imx95-headless-mode/SKILL.md) | Disable/enable display manager and DRM output | ⚠️ | ✅ |
| [`imx95-camera-setup`](skills/imx95-camera-setup/SKILL.md) | Detect MIPI-CSI cameras, test V4L2 capture pipeline | ✅ | ❌ |
| [`imx95-package`](skills/imx95-package/SKILL.md) | Install/remove/search packages (apt or opkg auto-detected) | ⚠️ | ❌ |

### Agents (multi-skill workflows)

| Agent | Description |
|-------|-------------|
| [`imx95-perf-investigator`](agents/imx95-perf-investigator.md) | End-to-end performance investigation: thermal → CPU/GPU/NPU freq → memory → IRQ → dmesg |

---

## Directory Layout

```
imx95-device-skills/
├── CLAUDE.md                   ← Primary Claude Code ingestion document
├── README.md                   ← This file
├── LICENSE                     ← Apache 2.0
├── install.sh                  ← One-time board setup script
├── .gitignore
│
├── agents/
│   ├── README.md
│   └── imx95-perf-investigator.md
│
├── lib/
│   ├── common.sh               ← Logging, guards, confirmation helpers
│   ├── sysfs.sh                ← Sysfs read helpers
│   └── board_detect.sh         ← Board/SoC variant detection
│
└── skills/
    ├── imx95-diagnostic/
    ├── imx95-print-device-info/
    ├── imx95-memory-audit/
    ├── imx95-npu-benchmark/
    ├── imx95-gpio-config/
    ├── imx95-headless-mode/
    ├── imx95-camera-setup/
    └── imx95-package/
```

Each skill directory contains:
- `SKILL.md` — machine-readable + human-readable spec (Claude reads this first)
- `scripts/` — executable shell scripts
- `evals/` — evaluation test cases
- `references/` — static reference material

---

## Safety Model

- **`safe: true`** — read-only, no side effects, Claude runs without asking.
- **`safe: false`** — may have side effects; Claude explains what it will do and asks for confirmation.
- **`destructive: true`** — modifies persistent state (eMMC, kernel cmdline, fuses); Claude requires explicit `YES` typed by the user before proceeding.

---

## Adding a New Skill

1. Copy an existing skill directory as a template.
2. Update `SKILL.md` front-matter (name, version, invoke_when, requires, safe, destructive).
3. Write `scripts/main.sh` — must source `../../lib/common.sh`, have a `usage()` function, use `log_*` helpers.
4. Add at least 3 eval cases to `evals/evals.json`.
5. Open a PR — CI runs all evals automatically.

See [`CLAUDE.md § 11`](CLAUDE.md#11-adding-a-new-skill) for the full checklist.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
