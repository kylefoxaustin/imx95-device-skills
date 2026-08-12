#!/bin/bash
# skills/imx95-gpio-config/scripts/gpio_list.sh
#
# Lists all GPIO chips and their lines using gpioinfo (libgpiod).
# Marks lines that are currently in use by a kernel driver or userspace consumer.
#
# Usage: gpio_list.sh [--chip CHIPNAME] [--used-only] [--free-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --chip NAME     Show only this chip (e.g., gpiochip0)
  --used-only     Show only lines currently in use
  --free-only     Show only free (unclaimed) lines
  -h, --help      Show this help
EOF
}

CHIP_FILTER=""
USED_ONLY=0
FREE_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chip)      CHIP_FILTER="$2"; shift 2 ;;
        --used-only) USED_ONLY=1; shift ;;
        --free-only) FREE_ONLY=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# Require gpioinfo
require_tool gpioinfo "Install with: apt-get install gpiod  OR  opkg install gpiod"

# ---------------------------------------------------------------------------
# Enumerate GPIO chips from /sys/bus/gpio/devices or /dev/gpiochip*
# ---------------------------------------------------------------------------
CHIPS=()
if [ -n "${CHIP_FILTER}" ]; then
    CHIPS=("${CHIP_FILTER}")
else
    for chip_dev in /dev/gpiochip*; do
        [ -e "${chip_dev}" ] && CHIPS+=("$(basename "${chip_dev}")")
    done
fi

if [ "${#CHIPS[@]}" -eq 0 ]; then
    log_error "No GPIO chips found. Is the GPIO driver loaded?"
    log_error "Check: ls /dev/gpiochip*"
    exit 1
fi

# ---------------------------------------------------------------------------
# Summary header
# ---------------------------------------------------------------------------
echo "=== GPIO CHIPS ==="
TOTAL_LINES=0
TOTAL_USED=0

for chip in "${CHIPS[@]}"; do
    chip_dev="/dev/${chip}"
    [ -e "${chip_dev}" ] || { log_warn "Chip ${chip} not found at ${chip_dev}"; continue; }

    # Get chip info
    chip_info=$(gpioinfo "${chip}" 2>/dev/null | head -1 || echo "${chip}: unknown")
    num_lines=$(gpioinfo "${chip}" 2>/dev/null | grep -c "^\s*line" || echo "0")
    used_lines=$(gpioinfo "${chip}" 2>/dev/null | grep -c "used" || echo "0")

    printf "%-14s  %s  (%d lines, %d used)\n" \
        "${chip}" "${chip_info}" "${num_lines}" "${used_lines}"

    TOTAL_LINES=$(( TOTAL_LINES + num_lines ))
    TOTAL_USED=$(( TOTAL_USED + used_lines ))
done

printf "\nTotal: %d lines across %d chips, %d in use, %d free\n" \
    "${TOTAL_LINES}" "${#CHIPS[@]}" "${TOTAL_USED}" "$(( TOTAL_LINES - TOTAL_USED ))"

# ---------------------------------------------------------------------------
# Detailed line listing per chip
# ---------------------------------------------------------------------------
for chip in "${CHIPS[@]}"; do
    chip_dev="/dev/${chip}"
    [ -e "${chip_dev}" ] || continue

    echo ""
    echo "=== GPIO LINES (${chip}) ==="
    printf "%-6s %-24s %-8s %-8s %-14s %s\n" \
        "Line" "Name" "State" "Dir" "Flags" "Consumer"
    printf "%-6s %-24s %-8s %-8s %-14s %s\n" \
        "----" "----" "-----" "---" "-----" "--------"

    # Parse gpioinfo output
    # Format: "line N: "NAME" CONSUMER INPUT/OUTPUT ACTIVE-HIGH/LOW [flags]"
    while IFS= read -r line; do
        # Skip chip header line
        echo "${line}" | grep -q "^gpiochip" && continue

        # Extract line number
        line_num=$(echo "${line}" | grep -oP '^\s*line\s+\K[0-9]+' || continue)
        [ -z "${line_num}" ] && continue

        # Extract name (quoted string or "unnamed")
        line_name=$(echo "${line}" | grep -oP '"[^"]*"' | head -1 | tr -d '"' || echo "unnamed")
        [ -z "${line_name}" ] && line_name="unnamed"

        # Used/unused
        if echo "${line}" | grep -q "used"; then
            state="used"
        else
            state="free"
        fi

        # Apply filters
        [ "${USED_ONLY}" = "1" ] && [ "${state}" = "free" ] && continue
        [ "${FREE_ONLY}" = "1" ] && [ "${state}" = "used" ] && continue

        # Direction
        if echo "${line}" | grep -qi "output"; then
            direction="output"
        else
            direction="input"
        fi

        # Active level
        if echo "${line}" | grep -qi "active-low"; then
            flags="active-low"
        else
            flags="active-high"
        fi

        # Consumer (kernel driver or userspace name)
        consumer=$(echo "${line}" | grep -oP '\[.*?\]' | tr -d '[]' || echo "")

        printf "%-6s %-24s %-8s %-8s %-14s %s\n" \
            "${line_num}" "${line_name}" "${state}" "${direction}" "${flags}" "${consumer}"

    done < <(gpioinfo "${chip}" 2>/dev/null)
done
