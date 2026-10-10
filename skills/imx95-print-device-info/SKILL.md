---
name: imx95-print-device-info
version: "0.1.0"
platform: imx95
invoke_when:
  - "what board is this"
  - "what kernel is running"
  - "quick board info"
  - "board identity"
  - "what is the hostname"
  - "what IP address does the board have"
  - "show me the board info"
  - "sanity check the board"
  - "what version of eIQ is installed"
requires:
  - bash
  - uname
  - cat
  - awk
  - ip
safe: true
destructive: false
---

# Skill: imx95-print-device-info

## Purpose

Prints a concise, one-screen board identity summary in under 2 seconds. Covers board model,
SoC revision, kernel version, uptime, IP address, eIQ version (if installed), rootfs
read/write state, and available disk space.

Use this skill:
- At the start of any session as a quick sanity check
- When the user asks "what board is this" or "what kernel is running"
- To prepend identity information to benchmark or diagnostic output
- As a fast alternative to `imx95-diagnostic` when only identity is needed

This skill is **read-only and safe**.

---

## Usage

```bash
bash skills/imx95-print-device-info/scripts/print_info.sh
```

No arguments required. Output is always one screen (~20 lines).

---

## Step-by-Step Procedure

1. Run `scripts/print_info.sh` via SSH.
2. Parse the output — each line is `KEY : VALUE` format.
3. Report the values to the user in a natural sentence, e.g.:
   *"This is an NXP FRDM-IMX95-PRO (compatible fsl,frdm-imx95-pro fsl,imx95) running Yocto Linux 6.18, up for 2h 14m.
   IP address is 192.168.1.42. eIQ 2.4.0 is installed. Root filesystem is read-write
   with 12 GB free."*

---

## Output Format

```
Board     : NXP FRDM-IMX95-PRO                       [MEASURED]
SoC       : i.MX95 rev2.0                            [MEASURED]
Compatible: fsl,frdm-imx95-pro fsl,imx95             [MEASURED]
Kernel    : 6.18.0 (Yocto; NOT 6.6.x)                [MEASURED]
Uptime    : <live>
Hostname  : imx95evk   ⚠️ NOT a board identity …     [MEASURED, non-unique]
IP        : <live>
eIQ       : <version> (/usr/bin/tensorflow-lite-2.19.0/examples/benchmark_model)
tflite-py : <version or "not installed">
RootFS    : rw (read-write)                          [MEASURED]
Disk /    : 8.7G free of 56G (84% used) on /dev/mmcblk1p2   [MEASURED 2026-10-09 — VOLATILE]
```

> ### ⚠️ The sample above is now MEASURED values, because the previous one was invented
> The earlier sample read `SoC : i.MX95 rev1.1`, `Hostname : imx95-evk`,
> `eIQ : 2.4.0 (/usr/bin/eiq-benchmark)` and `Disk / : 12G free of 28G`. **Every one of those four
> was fabricated**, and three contradict measured facts: this SoC is **rev 2.0**, the hostname is
> **`imx95evk`** (no hyphen), `/usr/bin/eiq-benchmark` **does not exist on this board**, and `28G`
> is roughly the **eMMC** capacity while `/` lives on the **56 G SD card**.
>
> **A sample output is a claim.** A reader calibrates from it — someone who saw `28G` would
> reasonably conclude `/` is on the eMMC, which is the device-vs-mount-point confusion this repo
> has a law about. Live fields are marked `<live>` rather than given plausible-looking values.
>
> ⚠️ **`Disk /` is volatile** — `/` shed 10 GB in two days (ground-truth §5). Treat the figure above
> as an example of the *format*, never as the current state.

---

## Caveats

- eIQ version detection searches common install paths. If eIQ is installed in a
  non-standard location, it may show "not detected".
- IP address shows the first non-loopback IPv4 address found. On boards with multiple
  interfaces, only one is shown.
- If the board has no network connection, IP shows "no network".
