---
name: imx95-headless-mode
version: "0.1.0"
platform: imx95
invoke_when:
  - "set the board to headless mode"
  - "disable the display"
  - "turn off the display manager"
  - "disable DRM"
  - "headless mode"
  - "no display needed"
  - "free up GPU memory"
  - "disable HDMI"
  - "what display is connected"
  - "show display configuration"
requires:
  - bash
  - systemctl
safe: false
destructive: true
---

# Skill: imx95-headless-mode

## Purpose

Shows the current display configuration and optionally disables the display manager and
DRM output to run the board in headless mode. Headless mode frees GPU memory, reduces
power consumption, and eliminates display-related latency for compute-only workloads.

**This skill is destructive** — `apply.sh` modifies systemd service state and may modify
kernel command line parameters. Changes may require a reboot to take full effect.
Claude must present a summary of changes and receive explicit `YES` confirmation before
running `apply.sh`.

Use this skill:
- When the user wants to run the board headless (no monitor attached)
- To free GPU/display memory for NPU or camera workloads
- When the display manager is consuming CPU/memory unnecessarily
- To check what display hardware is currently active

---

## Usage

```bash
# Show current display state (safe, read-only)
bash skills/imx95-headless-mode/scripts/plan.sh

# Apply headless mode (DESTRUCTIVE — requires YES confirmation)
bash skills/imx95-headless-mode/scripts/apply.sh
```

---

## Step-by-Step Procedure

### Checking display state (always safe)
1. Run `plan.sh` — shows DRM connectors, active display manager, framebuffer state.
2. Report to user: what display is connected, what service manages it, what would change.

### Applying headless mode (destructive)
1. Run `plan.sh` first and present the summary to the user.
2. Ask: *"This will stop [display-manager-name] and disable it on boot. Type YES to confirm."*
3. Only after explicit `YES`: run `apply.sh`.
4. Run `plan.sh` again to confirm the new state.
5. Advise user whether a reboot is needed.

---

## What apply.sh Does

1. Detects the active display manager (weston, gdm3, lightdm, sddm, or none).
2. Stops the display manager service: `systemctl stop <dm>`
3. Disables it from starting on boot: `systemctl disable <dm>`
4. If a framebuffer console is active, blanks it: `echo 1 > /sys/class/graphics/fb0/blank`
5. Reports new state.

**Does NOT modify:** kernel cmdline, U-Boot env, device tree, or any persistent flash.
To permanently disable DRM at the kernel level, the user must add `video=HDMI-A-1:d` to
kernel cmdline in U-Boot — `apply.sh` prints the exact command but does not run it.

---

## Caveats

- If no display manager is running, `apply.sh` reports "already headless" and exits.
- Stopping weston may kill any Wayland applications currently running.
- The board can be returned to display mode by running:
  `systemctl enable --now <display-manager-name>`
- On some BSP images, the display manager is started by a custom init script rather than
  systemd. `apply.sh` handles this case by checking `/etc/init.d/` as a fallback.
