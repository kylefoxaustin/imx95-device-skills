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
# shellcheck source=lib/neutron.sh
source "${REPO_ROOT}/lib/neutron.sh"   # neutron_find_runner — the ONLY runner discovery

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

# eIQ / TFLite runner detection.
#
# ⚠️ THIS USED TO SEARCH FIVE INVENTED PATHS: /usr/bin/eiq-benchmark,
# /usr/local/bin/eiq-benchmark, /opt/eiq/bin/eiq-benchmark, plus version files at
# /usr/share/eiq/version and /etc/eiq-version. NONE of those exist on this board.
# The measured location is /usr/bin/tensorflow-lite-2.19.0/examples/benchmark_model
# — a VERSIONED directory that is not on PATH, so `command -v benchmark_model`
# misses it too. Net effect: this skill reported eIQ "not detected" on a board
# where the runner is present and working. A FALSE NEGATIVE ON A REAL
# CAPABILITY — the delegate bug's mirror image, and just as misleading, because
# an agent told "no runner" will not try to benchmark at all.
#
# Fixed by delegating to lib/neutron.sh:neutron_find_runner, which is the single
# source of runner discovery for this repo. If the path ever changes it changes
# in ONE place. See references/imx95-ground-truth.md §5.
EIQ_STR="not detected"
RUNNER="$(neutron_find_runner 2>/dev/null || true)"
if [ -n "${RUNNER}" ]; then
    EIQ_VER="$("${RUNNER}" --version 2>/dev/null | head -1 \
               | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ -n "${EIQ_VER}" ]; then
        EIQ_STR="${EIQ_VER} (${RUNNER})"
    else
        EIQ_STR="present, version not reported (${RUNNER})"
    fi
fi

# Python tflite_runtime is a SEPARATE stack, not a fallback for the above —
# report it independently rather than only when the runner is missing.
TFLRT_STR="not installed"
if TFL_VER="$(python3 -c 'import tflite_runtime; print(tflite_runtime.__version__)' 2>/dev/null)"; then
    [ -n "${TFL_VER}" ] && TFLRT_STR="${TFL_VER}"
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
    # Name the DEVICE, not just the mount point. On this board `/` is
    # /dev/mmcblk1p2 — the SD card — while the eMMC is a different device
    # entirely. A free-space figure attached to a bare "/" invites the reader to
    # assume eMMC. See ground-truth §0 (reestablish-the-referent-law, tier 2).
    ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || echo 'unresolved')"
    DISK_STR="${DISK_FREE} free of ${DISK_SIZE} (${DISK_PCT} used) on ${ROOT_DEV}"
fi

# ---------------------------------------------------------------------------
# Print output
# ---------------------------------------------------------------------------
printf "%-10s: %s\n" "Board"      "${MODEL}"
printf "%-10s: %s rev%s\n" "SoC"  "${SOC_ID}" "${SOC_REV}"
printf "%-10s: %s\n" "Compatible" "${COMPAT}"
printf "%-10s: %s\n" "Kernel"     "${KERNEL}"
printf "%-10s: %s\n" "Uptime"     "${UPTIME_STR}"
printf "%-10s: %s%s\n" "Hostname"   "${HOSTNAME_VAL}" "   ⚠️ NOT a board identity — two fleet boards answer to 'imx95evk'; identify by Board/Compatible above"
printf "%-10s: %s\n" "IP"         "${IP_STR}"
printf "%-10s: %s\n" "eIQ"        "${EIQ_STR}"
printf "%-10s: %s\n" "tflite-py"  "${TFLRT_STR}"
printf "%-10s: %s\n" "RootFS"     "${ROOTFS_STATE}"
printf "%-10s: %s\n" "Disk /"     "${DISK_STR}"
