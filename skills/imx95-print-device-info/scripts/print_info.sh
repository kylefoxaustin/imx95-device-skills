#!/bin/bash
# skills/imx95-print-device-info/scripts/print_info.sh
#
# Prints a concise one-screen board identity summary.
# Completes in under 2 seconds. No arguments needed.
#
# Output format: KEY : VALUE (one per line)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source shared libraries
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/sysfs.sh
source "${REPO_ROOT}/lib/sysfs.sh"
# shellcheck source=lib/board_detect.sh
source "${REPO_ROOT}/lib/board_detect.sh"

usage() {
    echo "Usage: $(basename "$0")"
    echo "Prints a one-screen board identity summary. No arguments."
}

[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage && exit 0

# ---------------------------------------------------------------------------
# Collect values
# ---------------------------------------------------------------------------

# Board model and SoC
MODEL="${BOARD_MODEL}"
SOC_ID="${BOARD_SOC}"
SOC_REV="${BOARD_REV}"
COMPAT="${BOARD_COMPAT}"

# Kernel
KERNEL=$(uname -r)

# Uptime
UPTIME_SECS=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
UPTIME_H=$(( UPTIME_SECS / 3600 ))
UPTIME_M=$(( (UPTIME_SECS % 3600) / 60 ))
UPTIME_STR="${UPTIME_H}h ${UPTIME_M}m"

# Hostname
HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")

# IP address — first non-loopback IPv4
IP_STR="no network"
if command -v ip &>/dev/null; then
    IP_INFO=$(ip -4 -brief addr show 2>/dev/null | grep -v "^lo " | grep "UP\|UNKNOWN" | head -1 || true)
    if [ -n "${IP_INFO}" ]; then
        IFACE=$(echo "${IP_INFO}" | awk '{print $1}')
        ADDR=$(echo "${IP_INFO}" | awk '{print $3}' | cut -d/ -f1)
        [ -n "${ADDR}" ] && IP_STR="${ADDR} (${IFACE})"
    fi
fi

# eIQ version detection
EIQ_STR="not detected"
for candidate in \
    /usr/bin/eiq-benchmark \
    /usr/local/bin/eiq-benchmark \
    /opt/eiq/bin/eiq-benchmark \
    /usr/bin/benchmark_model \
    /usr/local/bin/benchmark_model; do
    if [ -x "${candidate}" ]; then
        # Try to extract version from the binary or adjacent version file
        EIQ_VER=""
        # Check for a version file next to the binary
        BIN_DIR=$(dirname "${candidate}")
        for vfile in "${BIN_DIR}/../version" "${BIN_DIR}/../VERSION" \
                     "/usr/share/eiq/version" "/etc/eiq-version"; do
            if [ -f "${vfile}" ]; then
                EIQ_VER=$(cat "${vfile}" 2>/dev/null | head -1 | tr -d '[:space:]')
                break
            fi
        done
        # Try --version flag
        if [ -z "${EIQ_VER}" ]; then
            EIQ_VER=$("${candidate}" --version 2>/dev/null | head -1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        fi
        if [ -n "${EIQ_VER}" ]; then
            EIQ_STR="${EIQ_VER} (${candidate})"
        else
            EIQ_STR="installed (${candidate})"
        fi
        break
    fi
done

# Also check for Python tflite_runtime
if [ "${EIQ_STR}" = "not detected" ]; then
    if python3 -c "import tflite_runtime; print(tflite_runtime.__version__)" &>/dev/null 2>&1; then
        TFL_VER=$(python3 -c "import tflite_runtime; print(tflite_runtime.__version__)" 2>/dev/null || echo "unknown")
        EIQ_STR="tflite_runtime ${TFL_VER} (python3)"
    fi
fi

# Root filesystem read/write state
ROOTFS_STATE="unknown"
if mount 2>/dev/null | grep -E "^[^ ]+ on / " | grep -q '\bro\b'; then
    ROOTFS_STATE="ro (read-only)"
else
    ROOTFS_STATE="rw (read-write)"
fi

# Disk space for /
DISK_STR="unknown"
if command -v df &>/dev/null; then
    DISK_INFO=$(df -h / 2>/dev/null | tail -1)
    DISK_SIZE=$(echo "${DISK_INFO}" | awk '{print $2}')
    DISK_USED=$(echo "${DISK_INFO}" | awk '{print $3}')
    DISK_FREE=$(echo "${DISK_INFO}" | awk '{print $4}')
    DISK_PCT=$(echo "${DISK_INFO}"  | awk '{print $5}')
    DISK_STR="${DISK_FREE} free of ${DISK_SIZE} (${DISK_PCT} used)"
fi

# ---------------------------------------------------------------------------
# Print output
# ---------------------------------------------------------------------------
printf "%-10s: %s\n" "Board"      "${MODEL}"
printf "%-10s: %s rev%s\n" "SoC"  "${SOC_ID}" "${SOC_REV}"
printf "%-10s: %s\n" "Compatible" "${COMPAT}"
printf "%-10s: %s\n" "Kernel"     "${KERNEL}"
printf "%-10s: %s\n" "Uptime"     "${UPTIME_STR}"
printf "%-10s: %s\n" "Hostname"   "${HOSTNAME_VAL}"
printf "%-10s: %s\n" "IP"         "${IP_STR}"
printf "%-10s: %s\n" "eIQ"        "${EIQ_STR}"
printf "%-10s: %s\n" "RootFS"     "${ROOTFS_STATE}"
printf "%-10s: %s\n" "Disk /"     "${DISK_STR}"
