#!/bin/bash
# skills/imx95-gpio-config/scripts/gpio_read.sh
#
# Reads the current value of a named GPIO line using gpioget (libgpiod).
# Validates that the chip and line exist before attempting to read.
#
# Usage: gpio_read.sh <chip> <line>
#   chip  — GPIO chip name (e.g., gpiochip0) or chip label
#   line  — Line number (integer) or line name (string)
#
# Examples:
#   gpio_read.sh gpiochip0 5
#   gpio_read.sh gpiochip2 reset-n

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <chip> <line>

Arguments:
  chip    GPIO chip name (e.g., gpiochip0, gpiochip1)
  line    Line number (0-31) or line name string

Examples:
  $(basename "$0") gpiochip0 5
  $(basename "$0") gpiochip2 reset-n

Output:
  Prints 0 (low) or 1 (high) followed by line metadata.
EOF
}

if [[ $# -lt 2 ]] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage
    exit 0
fi

CHIP="$1"
LINE="$2"

# Require gpioget and gpioinfo
require_tool gpioget  "Install with: apt-get install gpiod  OR  opkg install gpiod"
require_tool gpioinfo "Install with: apt-get install gpiod  OR  opkg install gpiod"

# ---------------------------------------------------------------------------
# Validate chip exists
# ---------------------------------------------------------------------------
CHIP_DEV="/dev/${CHIP}"
if [ ! -e "${CHIP_DEV}" ]; then
    log_error "GPIO chip '${CHIP}' not found at ${CHIP_DEV}"
    log_error "Available chips:"
    ls /dev/gpiochip* 2>/dev/null | sed 's/^/  /' || echo "  (none found)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate line exists on this chip
# ---------------------------------------------------------------------------
# Get total line count for this chip
CHIP_INFO=$(gpioinfo "${CHIP}" 2>/dev/null | head -1 || echo "")
NUM_LINES=$(gpioinfo "${CHIP}" 2>/dev/null | grep -c "^\s*line" || echo "0")

# If LINE is a number, check it's in range
if [[ "${LINE}" =~ ^[0-9]+$ ]]; then
    if [ "${LINE}" -ge "${NUM_LINES}" ]; then
        log_error "Line ${LINE} is out of range for ${CHIP} (has ${NUM_LINES} lines: 0–$(( NUM_LINES - 1 )))"
        exit 1
    fi
    LINE_NUM="${LINE}"
    # Get line name from gpioinfo
    LINE_NAME=$(gpioinfo "${CHIP}" 2>/dev/null | \
        awk "/^\s*line\s+${LINE}:/{match(\$0, /\"[^\"]*\"/, a); print a[0]}" | tr -d '"' || echo "unnamed")
    [ -z "${LINE_NAME}" ] && LINE_NAME="unnamed"
else
    # LINE is a name — find its number
    LINE_NUM=$(gpioinfo "${CHIP}" 2>/dev/null | \
        grep "\"${LINE}\"" | grep -oP '^\s*line\s+\K[0-9]+' | head -1 || echo "")
    if [ -z "${LINE_NUM}" ]; then
        log_error "Line named '${LINE}' not found on ${CHIP}"
        log_error "Use gpio_list.sh to see available line names"
        exit 1
    fi
    LINE_NAME="${LINE}"
fi

# ---------------------------------------------------------------------------
# Check if line is in use (warn but don't block reads)
# ---------------------------------------------------------------------------
LINE_INFO=$(gpioinfo "${CHIP}" 2>/dev/null | awk "/^\s*line\s+${LINE_NUM}:/{print}" || echo "")
IS_USED=0
echo "${LINE_INFO}" | grep -q "used" && IS_USED=1
CONSUMER=$(echo "${LINE_INFO}" | grep -oP '\[.*?\]' | tr -d '[]' || echo "")
DIRECTION="input"
echo "${LINE_INFO}" | grep -qi "output" && DIRECTION="output"

if [ "${IS_USED}" = "1" ]; then
    log_warn "Line ${LINE_NUM} ('${LINE_NAME}') is claimed by: ${CONSUMER:-kernel}"
    log_warn "Read may fail if the driver does not allow userspace access."
fi

# ---------------------------------------------------------------------------
# Read the GPIO value
# ---------------------------------------------------------------------------
VALUE=$(gpioget "${CHIP}" "${LINE_NUM}" 2>/dev/null) || {
    log_error "Failed to read GPIO ${CHIP} line ${LINE_NUM}."
    log_error "The line may be exclusively held by a kernel driver."
    exit 1
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
VALUE_STR="LOW (0)"
[ "${VALUE}" = "1" ] && VALUE_STR="HIGH (1)"

printf "%-12s: %s line %s\n" "Chip"      "${CHIP}" "${CHIP_INFO}"
printf "%-12s: %s ('%s')\n"  "Line"      "${LINE_NUM}" "${LINE_NAME}"
printf "%-12s: %s\n"         "Direction" "${DIRECTION}"
printf "%-12s: %s\n"         "Consumer"  "${CONSUMER:-none}"
printf "%-12s: %s\n"         "Value"     "${VALUE_STR}"

# Machine-readable last line for parsing
echo "VALUE=${VALUE}"
