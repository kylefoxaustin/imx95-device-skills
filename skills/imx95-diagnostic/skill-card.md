# imx95-diagnostic — Skill Card

**Version:** 0.1.0 | **Platform:** i.MX 95 | **Safe:** Yes | **Destructive:** No

## What It Does
Full board snapshot: CPU topology + frequencies, memory, all thermal zones, GPU/NPU state,
storage, network, USB, PCIe, remoteproc (M7/M33), systemd services, dmesg errors.

## When to Use
- "Run diagnostics" / "What's the state of the board?"
- Before any benchmark or heavy workload (baseline capture)
- After a crash, reboot, or unexpected behavior
- First step in `imx95-perf-investigator`

## Quick Invocation
```bash
bash skills/imx95-diagnostic/scripts/snapshot.sh
```

## Key Output Sections
`BOARD IDENTITY` · `CPU` · `THERMAL` · `MEMORY` · `GPU` · `NPU` · `STORAGE` ·
`NETWORK` · `USB` · `PCIE` · `REMOTEPROC` · `SERVICES` · `DMESG ERRORS`

## Alert Thresholds
| Metric | Warn | Alert |
|--------|------|-------|
| CPU temp | > 75°C | > 85°C |
| Available RAM | < 256 MB | < 128 MB |
| CMA free | < 30% | < 10% |
| CPU freq under load | < 1200 MHz | < 600 MHz |

## Dependencies
`bash`, `awk`, `grep`, `dmesg`, `df`, `ip`, `lsmod`
Optional: `lsusb`, `lspci`, `systemctl`
