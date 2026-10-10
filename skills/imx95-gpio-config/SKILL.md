---
name: imx95-gpio-config
version: "0.1.0"
platform: imx95
invoke_when:
  - "list GPIO lines"
  - "show GPIO"
  - "read a GPIO"
  - "write a GPIO"
  - "toggle GPIO"
  - "what GPIOs are available"
  - "which GPIO lines are in use"
  - "set GPIO high"
  - "set GPIO low"
  - "check GPIO state"
requires:
  - bash
  - gpioinfo
  - gpioget
  - gpioset
safe: false          # was `true` — WRONG: this skill drives GPIO lines
destructive: false   # the write is not PERSISTENT, but it is not side-effect-free either
---

> ## 🔴 SAFETY RECLASSIFIED: `safe: true` → `safe: false`
>
> This skill's front matter claimed **`safe: true`**, which in `CLAUDE.md`'s safety model means
> *"read-only, no side effects, Claude runs without asking."* **It is none of those things.** Its own
> `invoke_when` list includes *"write a GPIO"*, *"set GPIO high"*, *"set GPIO low"*; `gpio_write.sh`
> drives lines with `gpioset`; and that script already warns *"gpioset will attempt to drive it as
> output — this may conflict with hardware."*
>
> **The metadata is what decides whether an agent asks.** A correct in-script confirmation prompt
> does not help if the harness was told no confirmation is needed — the same shape as a warning
> printed above a number: present, correct, and bypassed.
>
> ⚠️ **On a dev board, GPIO lines are wired to things.** Resets, power enables, PMIC signals,
> display enables. Driving one is not a read.
>
> **Why the whole skill is reclassified and not just the write path:** it bundles `gpio_list.sh` and
> `gpio_read.sh` (genuinely safe) with `gpio_write.sh` (not). **An aggregate takes the risk class of
> its most dangerous operation** — that is the fail-closed direction, and the one that cannot
> surprise anyone. `list` and `read` remain safe to run; the *skill* is no longer marked
> run-without-asking.
>
> `destructive` stays `false` deliberately: a driven line does not survive a power cycle, and
> `destructive: true` in this repo means *persistent* state (eMMC, kernel cmdline, fuses). Not
> every unsafe thing is destructive, and conflating them would make the stronger flag meaningless.

# Skill: imx95-gpio-config

## Purpose

Lists, reads, and writes GPIO lines on the i.MX 95 using the modern `libgpiod` userspace
API (`gpioinfo`, `gpioget`, `gpioset`). Avoids the deprecated `/sys/class/gpio` sysfs
interface. Includes a safety blocklist of known-critical GPIO lines that must not be
written without explicit override.

Use this skill:
- When the user asks "show me all GPIO lines" or "what GPIOs are available"
- To read the current state of a GPIO line
- To drive a GPIO output high or low
- When debugging hardware connections on the FRDM-IMX95 EVK expansion headers

**Safety note:** `gpio_list.sh` and `gpio_read.sh` are safe (read-only). `gpio_write.sh`
has a safety gate that blocks writes to known-critical lines (power enables, reset lines,
boot mode pins) and requires explicit confirmation for any output write.

---

## Usage

```bash
# List all GPIO chips and lines
bash skills/imx95-gpio-config/scripts/gpio_list.sh

# Read a GPIO line
bash skills/imx95-gpio-config/scripts/gpio_read.sh <chip> <line>
# Example: gpio_read.sh gpiochip2 5

# Write a GPIO line
bash skills/imx95-gpio-config/scripts/gpio_write.sh <chip> <line> <0|1>
# Example: gpio_write.sh gpiochip2 5 1
```

---

## Step-by-Step Procedure

### Listing GPIOs
1. Run `gpio_list.sh` — calls `gpioinfo` for all chips.
2. Parse output: note which lines are `[used]` (claimed by a driver) vs free.
3. Report total chips, total lines, and count of used/free lines.

### Reading a GPIO
1. Confirm the chip and line exist (gpio_list.sh output).
2. Run `gpio_read.sh <chip> <line>`.
3. Report the value (0=low, 1=high) and the line's consumer name if it has one.

### Writing a GPIO
1. Confirm the line is not in the blocklist (gpio_write.sh checks automatically).
2. Confirm the line is configured as output (or not claimed by a driver).
3. Run `gpio_write.sh <chip> <line> <0|1>`.
4. Verify by reading back with `gpio_read.sh`.

---

## Output Format

```
=== GPIO CHIPS ===
gpiochip0  [30200000.gpio]  32 lines
gpiochip1  [30210000.gpio]  32 lines
...

=== GPIO LINES (gpiochip0) ===
line  0: unnamed         unused  input  active-high
line  1: "reset-n"       used    output active-low   [kernel]
...
```

---

## Caveats

- `gpioinfo`, `gpioget`, `gpioset` require the `gpiod` package (`libgpiod-tools`).
  Install with: `apt-get install gpiod` or `opkg install gpiod`.
- Writing to a GPIO line that is already claimed by a kernel driver will fail with
  "Device or resource busy". The script reports this clearly.
- The blocklist in `gpio_write.sh` covers known-critical lines on the FRDM-IMX95 EVK.
  Custom boards may have different critical lines — update the blocklist accordingly.
- `gpioset` holds the line value only while the process runs. For persistent output,
  use a background process or a kernel driver.
