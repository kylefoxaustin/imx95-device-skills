#!/bin/bash
# skills/imx95-diagnostic/scripts/detect_imx95.sh
#
# Verifies that the current board is an i.MX 95.
# Exits 0 if confirmed, exits 1 with a clear error message if not.
#
# Usage: detect_imx95.sh [--quiet]
#
# In quiet mode, prints nothing — just returns exit code.
# In normal mode, prints a confirmation or error message.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=skills/imx95-diagnostic/scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--quiet]

Verifies this board is an i.MX 95. Exits 0 on success, 1 on failure.

Options:
  --quiet    Suppress all output (exit code only)
  -h, --help Show this help
EOF
}

QUIET=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet)   QUIET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Check 1: /sys/firmware/devicetree/base/compatible
# ---------------------------------------------------------------------------
COMPAT_FILE="/sys/firmware/devicetree/base/compatible"
PROC_COMPAT="/proc/device-tree/compatible"

COMPAT_SRC=""
if [ -f "${COMPAT_FILE}" ]; then
    COMPAT_SRC="${COMPAT_FILE}"
elif [ -f "${PROC_COMPAT}" ]; then
    COMPAT_SRC="${PROC_COMPAT}"
fi

if [ -z "${COMPAT_SRC}" ]; then
    [ "${QUIET}" = "0" ] && log_error "Cannot read device tree compatible string."
    [ "${QUIET}" = "0" ] && log_error "Is this a Linux board with device tree support?"
    exit 1
fi

# Read NUL-separated compatible list
COMPAT_LIST=$(tr '\0' '\n' < "${COMPAT_SRC}" 2>/dev/null | grep -v '^$')
FIRST_COMPAT=$(echo "${COMPAT_LIST}" | head -1)

if ! echo "${COMPAT_LIST}" | grep -qi "imx95"; then
    [ "${QUIET}" = "0" ] && {
        log_error "This board is NOT an i.MX 95."
        log_error "Compatible string: ${FIRST_COMPAT}"
        log_error "Full compatible list:"
        echo "${COMPAT_LIST}" | sed 's/^/  /'
        log_error "This skill set requires an NXP i.MX 95 SoC."
    }
    exit 1
fi

# ---------------------------------------------------------------------------
# Check 2: /sys/devices/soc0/soc_id (if available)
# ---------------------------------------------------------------------------
SOC_ID_FILE="/sys/devices/soc0/soc_id"
SOC_ID="unknown"
if [ -f "${SOC_ID_FILE}" ]; then
    SOC_ID=$(tr -d '\0' < "${SOC_ID_FILE}" 2>/dev/null || echo "unknown")
    if ! echo "${SOC_ID}" | grep -qi "imx95\|i\.mx95"; then
        [ "${QUIET}" = "0" ] && {
            log_warn "compatible string contains 'imx95' but soc_id='${SOC_ID}' — proceeding anyway."
        }
    fi
fi

# ---------------------------------------------------------------------------
# Check 3: Model string
# ---------------------------------------------------------------------------
MODEL_FILE="/sys/firmware/devicetree/base/model"
BOARD_MODEL="unknown"
[ -f "${MODEL_FILE}" ] && BOARD_MODEL=$(tr -d '\0' < "${MODEL_FILE}" 2>/dev/null || echo "unknown")

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------
if [ "${QUIET}" = "0" ]; then
    log_info "Board confirmed: i.MX 95"
    printf "  %-14s: %s\n" "Model"      "${BOARD_MODEL}"
    printf "  %-14s: %s\n" "SoC ID"     "${SOC_ID}"
    printf "  %-14s: %s\n" "Compatible" "${FIRST_COMPAT}"
fi

exit 0
