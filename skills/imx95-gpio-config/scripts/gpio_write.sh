#!/bin/bash
# skills/imx95-gpio-config/scripts/gpio_write.sh
#
# Writes a value (0 or 1) to a GPIO output line using gpioset (libgpiod).
# Checks the line against a blocklist of known-critical GPIOs on the
# FRDM-IMX95 EVK before writing. Requires explicit confirmation for any write.
#
# Usage: gpio_write.sh <chip> <line> <0|1>
#
# Examples:
#   gpio_write.sh gpiochip2 5 1      # Set line 5 on gpiochip2 HIGH
#   gpio_write.sh gpiochip0 led0 0   # Set named line 'led0' LOW

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <chip> <line> <0|1>

Arguments:
  chip    GPIO chip name (e.g., gpiochip0)
  line    Line number (integer) or line name string
  value   0 (low/off) or 1 (high/on)

Options:
  --force     Skip blocklist check (USE WITH EXTREME CAUTION)
  --no-confirm  Skip interactive confirmation prompt
  -h, --help  Show this help

Safety:
  This script checks the line against a blocklist of known-critical GPIO lines
  on the FRDM-IMX95 EVK (power enables, reset lines, boot mode pins).
  Writing to these lines can crash the board or corrupt eMMC.
EOF
}

if [[ $# -lt 3 ]] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage
    exit 0
fi

CHIP="$1"
LINE="$2"
VALUE="$3"
FORCE=0
NO_CONFIRM=0

# Parse optional flags after positional args
shift 3
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)      FORCE=1; shift ;;
        --no-confirm) NO_CONFIRM=1; shift ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# Validate value
if [[ "${VALUE}" != "0" && "${VALUE}" != "1" ]]; then
    log_error "Value must be 0 or 1, got: '${VALUE}'"
    usage
    exit 1
fi

# Require tools
require_tool gpioset  "Install with: apt-get install gpiod  OR  opkg install gpiod"
require_tool gpioinfo "Install with: apt-get install gpiod  OR  opkg install gpiod"

# ---------------------------------------------------------------------------
# BLOCKLIST — known-critical GPIO lines on FRDM-IMX95 EVK
#
# Format: "CHIP:LINE_NUM_OR_NAME:REASON"
# These lines control power rails, reset signals, boot mode, and eMMC.
# Writing to them can cause immediate board crash, data corruption, or
# require physical power cycle to recover.
# ---------------------------------------------------------------------------
declare -a BLOCKLIST=(
    # Power enable lines (toggling cuts power to subsystems)
    "gpiochip0:0:PMIC_ON_REQ — PMIC power-on request; toggling cuts board power"
    "gpiochip0:1:VDD_USB_EN — USB power enable; disabling kills USB hub"
    "gpiochip0:2:VDD_PHY_EN — PHY power enable"
    "gpiochip0:3:PCIE_PWREN — PCIe power enable"

    # Reset lines (asserting reset crashes subsystems)
    "gpiochip1:0:ENET_RST_N — Ethernet PHY reset (active-low)"
    "gpiochip1:1:USB_HUB_RST_N — USB hub reset (active-low)"
    "gpiochip1:2:PCIE_RST_N — PCIe reset (active-low)"
    "gpiochip1:3:M7_RESET_N — Cortex-M7 reset"
    "gpiochip1:4:M33_RESET_N — Cortex-M33 reset"

    # Boot mode pins (changing during runtime causes undefined behavior)
    "gpiochip2:0:BOOT_MODE0 — Boot mode selection bit 0"
    "gpiochip2:1:BOOT_MODE1 — Boot mode selection bit 1"
    "gpiochip2:2:BOOT_MODE2 — Boot mode selection bit 2"
    "gpiochip2:3:BOOT_MODE3 — Boot mode selection bit 3"

    # eMMC control (writing can corrupt storage)
    "gpiochip3:0:EMMC_RST_N — eMMC reset (active-low); asserting corrupts filesystem"

    # Named lines (matched by name regardless of chip)
    ":pmic_on_req:PMIC power-on request"
    ":vdd_usb_en:USB power enable"
    ":enet_rst_n:Ethernet PHY reset"
    ":usb_hub_rst_n:USB hub reset"
    ":pcie_rst_n:PCIe reset"
    ":emmc_rst_n:eMMC reset — DO NOT WRITE"
    ":boot_mode:Boot mode pin"
)

# ---------------------------------------------------------------------------
# Validate chip
# ---------------------------------------------------------------------------
CHIP_DEV="/dev/${CHIP}"
if [ ! -e "${CHIP_DEV}" ]; then
    log_error "GPIO chip '${CHIP}' not found at ${CHIP_DEV}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve line number if name given
# ---------------------------------------------------------------------------
LINE_NUM="${LINE}"
LINE_NAME="${LINE}"

if ! [[ "${LINE}" =~ ^[0-9]+$ ]]; then
    # LINE is a name — find its number
    LINE_NUM=$(gpioinfo "${CHIP}" 2>/dev/null | \
        grep "\"${LINE}\"" | grep -oP '^\s*line\s+\K[0-9]+' | head -1 || echo "")
    if [ -z "${LINE_NUM}" ]; then
        log_error "Line named '${LINE}' not found on ${CHIP}"
        exit 1
    fi
else
    # LINE is a number — get its name
    LINE_NAME=$(gpioinfo "${CHIP}" 2>/dev/null | \
        awk "/^\s*line\s+${LINE}:/{match(\$0, /\"[^\"]*\"/, a); print a[0]}" | \
        tr -d '"' || echo "unnamed")
    [ -z "${LINE_NAME}" ] && LINE_NAME="unnamed"
fi

# ---------------------------------------------------------------------------
# Blocklist check
# ---------------------------------------------------------------------------
if [ "${FORCE}" = "0" ]; then
    for entry in "${BLOCKLIST[@]}"; do
        bl_chip=$(echo "${entry}" | cut -d: -f1)
        bl_line=$(echo "${entry}" | cut -d: -f2)
        bl_reason=$(echo "${entry}" | cut -d: -f3-)

        # Match by chip+line_num or chip+line_name or name-only (empty chip)
        MATCH=0
        if [ -n "${bl_chip}" ]; then
            # Chip-specific match
            if [ "${bl_chip}" = "${CHIP}" ]; then
                if [ "${bl_line}" = "${LINE_NUM}" ] || \
                   [ "${bl_line}" = "${LINE_NAME}" ]; then
                    MATCH=1
                fi
            fi
        else
            # Name-only match (any chip)
            if echo "${LINE_NAME}" | grep -qi "${bl_line}"; then
                MATCH=1
            fi
        fi

        if [ "${MATCH}" = "1" ]; then
            echo ""
            echo -e "\033[0;31m╔══════════════════════════════════════════════════════════╗\033[0m"
            echo -e "\033[0;31m║  BLOCKED — CRITICAL GPIO LINE                            ║\033[0m"
            echo -e "\033[0;31m╚══════════════════════════════════════════════════════════╝\033[0m"
            echo ""
            echo "  Chip : ${CHIP}"
            echo "  Line : ${LINE_NUM} ('${LINE_NAME}')"
            echo "  Reason: ${bl_reason}"
            echo ""
            echo "  Writing to this line can crash the board, corrupt eMMC,"
            echo "  or require a physical power cycle to recover."
            echo ""
            echo "  If you are CERTAIN this is safe, re-run with --force"
            echo "  (e.g., on a custom board where this line is repurposed)."
            exit 1
        fi
    done
fi

# ---------------------------------------------------------------------------
# Check line direction and usage
# ---------------------------------------------------------------------------
LINE_INFO=$(gpioinfo "${CHIP}" 2>/dev/null | awk "/^\s*line\s+${LINE_NUM}:/{print}" || echo "")
IS_USED=0
echo "${LINE_INFO}" | grep -q "used" && IS_USED=1
CONSUMER=$(echo "${LINE_INFO}" | grep -oP '\[.*?\]' | tr -d '[]' || echo "")
IS_INPUT=0
echo "${LINE_INFO}" | grep -qi "input" && ! echo "${LINE_INFO}" | grep -qi "output" && IS_INPUT=1

if [ "${IS_USED}" = "1" ]; then
    log_warn "Line ${LINE_NUM} ('${LINE_NAME}') is claimed by: ${CONSUMER:-kernel}"
    log_warn "Write will likely fail with 'Device or resource busy'."
fi

if [ "${IS_INPUT}" = "1" ]; then
    log_warn "Line ${LINE_NUM} ('${LINE_NAME}') appears to be configured as INPUT."
    log_warn "gpioset will attempt to drive it as output — this may conflict with hardware."
fi

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
VALUE_STR="HIGH (1)"; [ "${VALUE}" = "0" ] && VALUE_STR="LOW (0)"

if [ "${NO_CONFIRM}" = "0" ]; then
    echo ""
    echo "About to write GPIO:"
    echo "  Chip  : ${CHIP}"
    echo "  Line  : ${LINE_NUM} ('${LINE_NAME}')"
    echo "  Value : ${VALUE_STR}"
    echo ""
    echo -n "Confirm? [y/N] "
    read -r answer
    if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Write the GPIO
# ---------------------------------------------------------------------------
log_info "Writing ${CHIP} line ${LINE_NUM} = ${VALUE}..."

# gpioset holds the value while the process runs.
# For a one-shot write, we use --mode=exit (if supported) or a brief hold.
if gpioset --help 2>&1 | grep -q "\-\-mode"; then
    gpioset --mode=exit "${CHIP}" "${LINE_NUM}=${VALUE}" 2>/dev/null || {
        log_error "gpioset failed. Line may be held by kernel driver."
        exit 1
    }
else
    # Older gpioset: set and release immediately
    gpioset "${CHIP}" "${LINE_NUM}=${VALUE}" &
    GPIOSET_PID=$!
    sleep 0.1
    kill "${GPIOSET_PID}" 2>/dev/null || true
fi

log_info "GPIO write complete: ${CHIP} line ${LINE_NUM} ('${LINE_NAME}') = ${VALUE_STR}"

# Verify by reading back
READBACK=$(gpioget "${CHIP}" "${LINE_NUM}" 2>/dev/null || echo "read_failed")
if [ "${READBACK}" = "${VALUE}" ]; then
    log_info "Readback confirmed: value = ${READBACK}"
elif [ "${READBACK}" = "read_failed" ]; then
    log_warn "Could not read back value to confirm."
else
    log_warn "Readback value (${READBACK}) differs from written value (${VALUE})."
    log_warn "The line may be driven by hardware or another driver."
fi
