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
   *"This is an NXP i.MX95 19x19 EVK board running kernel 6.6.23, up for 2h 14m.
   IP address is 192.168.1.42. eIQ 2.4.0 is installed. Root filesystem is read-write
   with 12 GB free."*

---

## Output Format

```
Board     : NXP i.MX95 19x19 EVK board
SoC       : i.MX95 rev1.1
Compatible: fsl,imx95-19x19-evk
Kernel    : 6.6.23-lts-next+gabcdef1234
Uptime    : 2h 14m
Hostname  : imx95-evk
IP        : 192.168.1.42 (eth0)
eIQ       : 2.4.0 (/usr/bin/eiq-benchmark)
RootFS    : rw (read-write)
Disk /    : 12G free of 28G (43% used)
```

---

## Caveats

- eIQ version detection searches common install paths. If eIQ is installed in a
  non-standard location, it may show "not detected".
- IP address shows the first non-loopback IPv4 address found. On boards with multiple
  interfaces, only one is shown.
- If the board has no network connection, IP shows "no network".
