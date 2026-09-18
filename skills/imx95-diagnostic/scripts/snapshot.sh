#!/bin/bash
# skills/imx95-diagnostic/scripts/snapshot.sh
#
# Comprehensive i.MX 95 board snapshot.
# Collects: board identity, kernel, uptime, CPU (all 6 cores), memory,
# thermal zones, GPU devfreq, NPU state, storage, network, USB, PCIe,
# remoteproc state, systemd service count, last 20 dmesg errors.
#
# Output: structured text with "=== SECTION ===" headers.
# Claude parses each section independently.
#
# Usage: snapshot.sh [--section NAME] [--no-dmesg] [--quiet] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=skills/imx95-diagnostic/scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SECTIONS_FILTER=()
NO_DMESG=0
QUIET=0
JSON_OUTPUT=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --section NAME    Only output this section (repeatable). Names:
                    IDENTITY CPU THERMAL MEMORY GPU NPU STORAGE
                    NETWORK USB PCIE REMOTEPROC SERVICES DMESG
  --no-dmesg        Skip dmesg collection
  --quiet           Suppress decorative headers
  --json            Output JSON (experimental)
  -h, --help        Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --section CPU --section THERMAL
  $(basename "$0") --no-dmesg --quiet
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --section)   SECTIONS_FILTER+=("${2^^}"); shift 2 ;;
        --no-dmesg)  NO_DMESG=1; shift ;;
        --quiet)     QUIET=1; shift ;;
        --json)      JSON_OUTPUT=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Section filter helper
# ---------------------------------------------------------------------------
should_run() {
    local section="${1^^}"
    if [ "${#SECTIONS_FILTER[@]}" -eq 0 ]; then
        return 0  # no filter — run all
    fi
    for f in "${SECTIONS_FILTER[@]}"; do
        [ "${f}" = "${section}" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Header printer
# ---------------------------------------------------------------------------
section_header() {
    if [ "${QUIET}" = "0" ]; then
        echo ""
        echo "=== $1 ==="
    fi
}

# ---------------------------------------------------------------------------
# Snapshot timestamp
# ---------------------------------------------------------------------------
SNAP_TIME=$(timestamp)

if [ "${QUIET}" = "0" ] && [ "${#SECTIONS_FILTER[@]}" -eq 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         i.MX 95 Board Diagnostic Snapshot                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo "Captured: ${SNAP_TIME}"
fi

# ---------------------------------------------------------------------------
# SECTION: BOARD IDENTITY
# ---------------------------------------------------------------------------
if should_run "IDENTITY"; then
    section_header "BOARD IDENTITY"

    MODEL=$(get_board_model)
    SOC_ID=$(get_soc_id)
    SOC_REV=$(get_soc_rev)
    KERNEL=$(uname -r)
    HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown")

    # Uptime in human-readable form
    UPTIME_RAW=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo "0")
    UPTIME_H=$(echo "${UPTIME_RAW}" | awk '{h=int($1/3600); m=int(($1%3600)/60); printf "%dh %dm", h, m}')

    # Compatible string (first entry)
    COMPAT=$(tr '\0' '\n' < /sys/firmware/devicetree/base/compatible 2>/dev/null | head -1 || echo "unknown")

    printf "%-12s: %s\n" "Model"      "${MODEL}"
    printf "%-12s: %s rev%s\n" "SoC"  "${SOC_ID}" "${SOC_REV}"
    printf "%-12s: %s\n" "Compatible" "${COMPAT}"
    printf "%-12s: %s\n" "Kernel"     "${KERNEL}"
    printf "%-12s: %s\n" "Uptime"     "${UPTIME_H}"
    printf "%-12s: %s\n" "Hostname"   "${HOSTNAME_VAL}"
    printf "%-12s: %s\n" "Timestamp"  "${SNAP_TIME}"
fi

# ---------------------------------------------------------------------------
# SECTION: CPU
# ---------------------------------------------------------------------------
if should_run "CPU"; then
    section_header "CPU"

    # CPU topology from /proc/cpuinfo
    CPU_MODEL=$(grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
    CPU_COUNT=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "0")
    printf "%-14s: %s\n" "Model" "${CPU_MODEL}"
    printf "%-14s: %s\n" "Core count" "${CPU_COUNT}"
    echo ""

    # Per-core frequency, governor, online state
    printf "%-8s %-12s %-16s %-12s %-12s\n" "CPU" "State" "Cur Freq" "Governor" "Max Freq"
    printf "%-8s %-12s %-16s %-12s %-12s\n" "---" "-----" "--------" "--------" "--------"

    for n in 0 1 2 3 4 5; do
        cpu_path="/sys/devices/system/cpu/cpu${n}"
        [ -d "${cpu_path}" ] || continue

        # Online state (cpu0 has no online file — always online)
        if [ "${n}" -eq 0 ]; then
            online="online"
        else
            online_val=$(sysfs_read "${cpu_path}/online" "1")
            online=$( [ "${online_val}" = "1" ] && echo "online" || echo "OFFLINE" )
        fi

        if [ "${online}" = "OFFLINE" ]; then
            printf "%-8s %-12s\n" "cpu${n}" "OFFLINE"
            continue
        fi

        cur_khz=$(sysfs_read "${cpu_path}/cpufreq/scaling_cur_freq" "0")
        max_khz=$(sysfs_read "${cpu_path}/cpufreq/scaling_max_freq" "0")
        gov=$(sysfs_read "${cpu_path}/cpufreq/scaling_governor" "unknown")
        cur_mhz=$(( cur_khz / 1000 ))
        max_mhz=$(( max_khz / 1000 ))

        printf "%-8s %-12s %-16s %-12s %-12s\n" \
            "cpu${n}" "${online}" "${cur_mhz} MHz" "${gov}" "${max_mhz} MHz"
    done

    # Available governors and frequencies
    echo ""
    AVAIL_GOV=$(sysfs_read "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" "N/A")
    printf "%-14s: %s\n" "Governors" "${AVAIL_GOV}"

    AVAIL_FREQ=$(sysfs_read "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies" "N/A")
    if [ "${AVAIL_FREQ}" != "N/A" ]; then
        AVAIL_FREQ_MHZ=$(echo "${AVAIL_FREQ}" | tr ' ' '\n' | awk 'NF{printf "%d ", $1/1000}' | xargs)
        printf "%-14s: %s MHz\n" "Freq steps" "${AVAIL_FREQ_MHZ}"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: THERMAL
# ---------------------------------------------------------------------------
if should_run "THERMAL"; then
    section_header "THERMAL"

    printf "%-24s %-10s %-10s\n" "Zone" "Temp" "Status"
    printf "%-24s %-10s %-10s\n" "----" "----" "------"

    for zone_dir in /sys/class/thermal/thermal_zone*/; do
        [ -d "${zone_dir}" ] || continue
        zone_type=$(sysfs_read "${zone_dir}type" "unknown")
        temp_milli=$(sysfs_read "${zone_dir}temp" "0")
        temp_c=$(( temp_milli / 1000 ))

        status="OK"
        [ "${temp_c}" -ge 75 ] && status="WARM"
        [ "${temp_c}" -ge 85 ] && status="THROTTLING"
        [ "${temp_c}" -ge 95 ] && status="CRITICAL"

        printf "%-24s %-10s %-10s\n" "${zone_type}" "${temp_c}°C" "${status}"
    done

    # Active cooling devices
    echo ""
    COOLING_ACTIVE=0
    for cdev in /sys/class/thermal/cooling_device*/; do
        [ -d "${cdev}" ] || continue
        cdev_type=$(sysfs_read "${cdev}type" "unknown")
        cur_state=$(sysfs_read "${cdev}cur_state" "0")
        max_state=$(sysfs_read "${cdev}max_state" "0")
        if [ "${cur_state}" -gt 0 ]; then
            printf "ACTIVE COOLING: %-20s state=%s/%s\n" "${cdev_type}" "${cur_state}" "${max_state}"
            COOLING_ACTIVE=1
        fi
    done
    [ "${COOLING_ACTIVE}" = "0" ] && echo "Cooling devices: all idle (no active throttling)"
fi

# ---------------------------------------------------------------------------
# SECTION: MEMORY
# ---------------------------------------------------------------------------
if should_run "MEMORY"; then
    section_header "MEMORY"

    # Parse /proc/meminfo
    eval "$(awk '
        /^MemTotal:/     {printf "MEM_TOTAL_KB=%s\n",     $2}
        /^MemFree:/      {printf "MEM_FREE_KB=%s\n",      $2}
        /^MemAvailable:/ {printf "MEM_AVAIL_KB=%s\n",     $2}
        /^Cached:/       {printf "MEM_CACHED_KB=%s\n",    $2}
        /^Buffers:/      {printf "MEM_BUFFERS_KB=%s\n",   $2}
        /^SwapTotal:/    {printf "SWAP_TOTAL_KB=%s\n",    $2}
        /^SwapFree:/     {printf "SWAP_FREE_KB=%s\n",     $2}
        /^CmaTotal:/     {printf "CMA_TOTAL_KB=%s\n",     $2}
        /^CmaFree:/      {printf "CMA_FREE_KB=%s\n",      $2}
        /^VmallocUsed:/  {printf "VMALLOC_USED_KB=%s\n",  $2}
        /^Shmem:/        {printf "SHMEM_KB=%s\n",         $2}
    ' /proc/meminfo 2>/dev/null)"

    MEM_TOTAL_MB=$(( ${MEM_TOTAL_KB:-0} / 1024 ))
    MEM_AVAIL_MB=$(( ${MEM_AVAIL_KB:-0} / 1024 ))
    MEM_FREE_MB=$(( ${MEM_FREE_KB:-0} / 1024 ))
    MEM_CACHED_MB=$(( ${MEM_CACHED_KB:-0} / 1024 ))
    CMA_TOTAL_MB=$(( ${CMA_TOTAL_KB:-0} / 1024 ))
    CMA_FREE_MB=$(( ${CMA_FREE_KB:-0} / 1024 ))
    SWAP_TOTAL_MB=$(( ${SWAP_TOTAL_KB:-0} / 1024 ))
    SWAP_FREE_MB=$(( ${SWAP_FREE_KB:-0} / 1024 ))

    MEM_USED_PCT=0
    [ "${MEM_TOTAL_MB}" -gt 0 ] && \
        MEM_USED_PCT=$(( (MEM_TOTAL_MB - MEM_AVAIL_MB) * 100 / MEM_TOTAL_MB ))

    CMA_USED_PCT=0
    [ "${CMA_TOTAL_MB}" -gt 0 ] && \
        CMA_USED_PCT=$(( (CMA_TOTAL_MB - CMA_FREE_MB) * 100 / CMA_TOTAL_MB ))

    printf "%-18s: %d MB\n"          "Total RAM"       "${MEM_TOTAL_MB}"
    printf "%-18s: %d MB  (%d%% used)\n" "Available"   "${MEM_AVAIL_MB}" "${MEM_USED_PCT}"
    printf "%-18s: %d MB\n"          "Free (raw)"      "${MEM_FREE_MB}"
    printf "%-18s: %d MB\n"          "Page cache"      "${MEM_CACHED_MB}"
    printf "%-18s: %d MB total, %d MB free  (%d%% used)\n" \
        "CMA" "${CMA_TOTAL_MB}" "${CMA_FREE_MB}" "${CMA_USED_PCT}"
    printf "%-18s: %d MB total, %d MB free\n" \
        "Swap" "${SWAP_TOTAL_MB}" "${SWAP_FREE_MB}"
    printf "%-18s: %d MB\n" "VmallocUsed" "$(( ${VMALLOC_USED_KB:-0} / 1024 ))"

    # Memory pressure assessment
    echo ""
    if   [ "${MEM_AVAIL_MB}" -lt 128 ]; then
        echo "MEMORY STATUS: CRITICAL — less than 128 MB available. OOM kills likely."
    elif [ "${MEM_AVAIL_MB}" -lt 256 ]; then
        echo "MEMORY STATUS: HIGH PRESSURE — less than 256 MB available."
    elif [ "${CMA_USED_PCT}" -gt 80 ]; then
        echo "MEMORY STATUS: CMA PRESSURE — CMA is ${CMA_USED_PCT}% used. VPU/ISP/NPU allocations may fail."
    else
        echo "MEMORY STATUS: OK"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: GPU
# ---------------------------------------------------------------------------
if should_run "GPU"; then
    section_header "GPU"

    # GPU is an Arm Mali-G310 (1 core, r0p0) — NOT a Vivante GC7000UL (that is
    # i.MX8M Plus). It is graphics-only: OpenCL is an ICD stub, so it is not an
    # ML backend on this board. ground-truth §1.
    GPU_DEVFREQ=""
    for pattern in "*mali*" "*gpu*" "*gc*" "*vivante*" "*galcore*"; do
        found=$(ls -d /sys/class/devfreq/${pattern} 2>/dev/null | head -1 || true)
        [ -n "${found}" ] && GPU_DEVFREQ="${found}" && break
    done

    if [ -n "${GPU_DEVFREQ}" ]; then
        cur_hz=$(sysfs_read "${GPU_DEVFREQ}/cur_freq" "0")
        min_hz=$(sysfs_read "${GPU_DEVFREQ}/min_freq" "0")
        max_hz=$(sysfs_read "${GPU_DEVFREQ}/max_freq" "0")
        gov=$(sysfs_read "${GPU_DEVFREQ}/governor" "unknown")
        printf "%-14s: %s\n" "Driver path"  "${GPU_DEVFREQ}"
        printf "%-14s: %d MHz\n" "Cur freq"  "$(( cur_hz / 1000000 ))"
        printf "%-14s: %d – %d MHz\n" "Freq range" "$(( min_hz/1000000 ))" "$(( max_hz/1000000 ))"
        printf "%-14s: %s\n" "Governor"     "${gov}"
    else
        echo "GPU devfreq node not found."
        echo "  GPU may be idle, driver not loaded, or path differs from expected."
        echo "  Check: ls /sys/class/devfreq/"
    fi

    # DRM/KMS connector state
    echo ""
    echo "DRM connectors:"
    for conn in /sys/class/drm/card*-*/; do
        [ -d "${conn}" ] || continue
        conn_name=$(basename "${conn}")
        status=$(sysfs_read "${conn}status" "unknown")
        enabled=$(sysfs_read "${conn}enabled" "unknown")
        printf "  %-30s status=%-12s enabled=%s\n" "${conn_name}" "${status}" "${enabled}"
    done
    [ ! -d /sys/class/drm ] && echo "  DRM subsystem not found"
fi

# ---------------------------------------------------------------------------
# SECTION: NPU
# ---------------------------------------------------------------------------
if should_run "NPU"; then
    section_header "NPU"

    NPU_FOUND=0
    for path in /sys/bus/platform/drivers/neutron \
                /sys/bus/platform/drivers/ethosu \
                /sys/bus/platform/drivers/imx-neutron \
                /sys/bus/platform/drivers/neutron-npu; do
        if [ -d "${path}" ]; then
            printf "%-18s: %s\n" "Driver" "$(basename "${path}") (loaded)"
            printf "%-18s: %s\n" "Driver path" "${path}"
            NPU_FOUND=1
            break
        fi
    done

    # Check lsmod
    for mod in neutron ethosu imx_neutron; do
        if lsmod 2>/dev/null | grep -q "^${mod}[[:space:]]"; then
            printf "%-18s: %s\n" "Kernel module" "${mod} (loaded)"
            NPU_FOUND=1
        fi
    done

    # Device node
    for dev in /dev/neutron* /dev/ethosu*; do
        [ -e "${dev}" ] && printf "%-18s: %s\n" "Device node" "${dev}" && NPU_FOUND=1
    done

    [ "${NPU_FOUND}" = "0" ] && echo "NPU driver: NOT LOADED — check BSP and device tree"

    # eIQ Neutron delegate libraries.
    #
    # ⚠️ This block used to search libethosu_delegate.so (i.MX93's Ethos-U65) and
    # libvx_delegate.so (i.MX8M Plus's VeriSilicon VX), then print "NPU inference
    # will fall back to CPU". That sentence is how a CPU benchmark came to be
    # reported as an NPU number. See references/imx95-ground-truth.md §1.1.
    echo ""
    echo "Neutron delegate libraries (i.MX95 — TFLite stack):"
    DELEGATE_FOUND=0
    for lib in /usr/lib/libneutron_delegate.so \
               /usr/lib/liblitert_neutron_delegate.so; do
        if [ -f "${lib}" ]; then
            printf "  FOUND: %-44s (%s bytes)\n" "${lib}" "$(stat -c%s "${lib}" 2>/dev/null || echo '?')"
            DELEGATE_FOUND=1
        fi
    done
    if [ "${DELEGATE_FOUND}" = "0" ]; then
        echo "  NONE FOUND — no Neutron TFLite inference is possible on this board."
        echo "  Do NOT interpret any later latency as an NPU number."
    fi

    # ONNX Runtime Neutron EP — a SEPARATE stack with its own placement signal.
    echo ""
    echo "ONNX Runtime Neutron EP (LLM stack — independent of the delegate above):"
    ORT_FOUND=0
    for lib in /usr/lib/libonnxruntime.so.1.24.3 /usr/lib/libNeutronDriver.so; do
        [ -f "${lib}" ] && { printf "  FOUND: %s\n" "${lib}"; ORT_FOUND=1; }
    done
    [ "${ORT_FOUND}" = "0" ] && echo "  not present"

    # Other-SoC delegates: report loudly if present; never bind to them.
    for lib in /usr/lib/libethosu_delegate.so /usr/lib/libvx_delegate.so; do
        [ -f "${lib}" ] && echo "  ⚠️ WRONG-SoC DELEGATE PRESENT: ${lib} — not i.MX95, never load it here"
    done

    # benchmark_model tool
    echo ""
    if command -v benchmark_model &>/dev/null; then
        printf "%-18s: %s\n" "benchmark_model" "$(command -v benchmark_model)"
    else
        printf "%-18s: not found\n" "benchmark_model"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: STORAGE
# ---------------------------------------------------------------------------
if should_run "STORAGE"; then
    section_header "STORAGE"

    echo "Filesystem usage:"
    df -h 2>/dev/null | grep -v "^tmpfs\|^devtmpfs\|^udev" | \
        awk 'NR==1{printf "  %-20s %-8s %-8s %-8s %-6s %s\n",$1,$2,$3,$4,$5,$6; next}
             {printf "  %-20s %-8s %-8s %-8s %-6s %s\n",$1,$2,$3,$4,$5,$6}'

    echo ""
    echo "Block devices:"
    for dev in /sys/block/mmcblk* /sys/block/sd* /sys/block/nvme*; do
        [ -d "${dev}" ] || continue
        dev_name=$(basename "${dev}")
        size_sectors=$(sysfs_read "${dev}/size" "0")
        size_gb=$(( size_sectors * 512 / 1024 / 1024 / 1024 ))
        removable=$(sysfs_read "${dev}/removable" "0")
        ro=$(sysfs_read "${dev}/ro" "0")
        printf "  /dev/%-12s %4d GB  removable=%s  ro=%s\n" \
            "${dev_name}" "${size_gb}" "${removable}" "${ro}"
    done

    # Root filesystem mount flags
    echo ""
    ROOTFS_FLAGS=$(mount 2>/dev/null | grep " on / " | grep -oP '\(.*?\)' | head -1 || echo "unknown")
    printf "%-18s: %s\n" "Root mount flags" "${ROOTFS_FLAGS}"
fi

# ---------------------------------------------------------------------------
# SECTION: NETWORK
# ---------------------------------------------------------------------------
if should_run "NETWORK"; then
    section_header "NETWORK"

    if command -v ip &>/dev/null; then
        ip -brief addr show 2>/dev/null | \
            awk '{printf "  %-16s %-12s %s\n", $1, $2, $3}' || true
    else
        ifconfig 2>/dev/null | grep -E "^[a-z]|inet " | \
            awk '/^[a-z]/{iface=$1} /inet /{print "  "iface": "$2}' || true
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: USB
# ---------------------------------------------------------------------------
if should_run "USB"; then
    section_header "USB"

    if command -v lsusb &>/dev/null; then
        lsusb 2>/dev/null | sed 's/^/  /' || echo "  (no USB devices or lsusb failed)"
    else
        echo "  lsusb not available — listing /sys/bus/usb/devices:"
        for dev in /sys/bus/usb/devices/[0-9]*; do
            [ -d "${dev}" ] || continue
            vid=$(sysfs_read "${dev}/idVendor" "????")
            pid=$(sysfs_read "${dev}/idProduct" "????")
            mfr=$(sysfs_read "${dev}/manufacturer" "")
            prod=$(sysfs_read "${dev}/product" "")
            printf "  %s:%s  %s %s\n" "${vid}" "${pid}" "${mfr}" "${prod}"
        done
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: PCIE
# ---------------------------------------------------------------------------
if should_run "PCIE"; then
    section_header "PCIE"

    if command -v lspci &>/dev/null; then
        lspci 2>/dev/null | sed 's/^/  /' || echo "  (no PCIe devices or lspci failed)"
    else
        echo "  lspci not available — listing /sys/bus/pci/devices:"
        for dev in /sys/bus/pci/devices/*/; do
            [ -d "${dev}" ] || continue
            class=$(sysfs_read "${dev}class" "??????")
            vendor=$(sysfs_read "${dev}vendor" "????")
            device_id=$(sysfs_read "${dev}device" "????")
            printf "  %s  vendor=%s device=%s\n" "$(basename "${dev}")" "${vendor}" "${device_id}"
        done 2>/dev/null || echo "  No PCIe devices found"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: REMOTEPROC
# ---------------------------------------------------------------------------
if should_run "REMOTEPROC"; then
    section_header "REMOTEPROC"

    RPROC_COUNT=0
    for rp in /sys/bus/remoteproc/devices/remoteproc*/; do
        [ -d "${rp}" ] || continue
        rp_name=$(sysfs_read "${rp}name" "$(basename "${rp}")")
        rp_state=$(sysfs_read "${rp}state" "unknown")
        rp_fw=$(sysfs_read "${rp}firmware" "unknown")

        status_label="OK"
        [ "${rp_state}" = "crashed" ] && status_label="CRASHED — firmware failed!"
        [ "${rp_state}" = "offline" ] && status_label="offline (not started)"

        printf "  %-20s state=%-12s firmware=%-30s [%s]\n" \
            "${rp_name}" "${rp_state}" "${rp_fw}" "${status_label}"
        RPROC_COUNT=$(( RPROC_COUNT + 1 ))
    done

    [ "${RPROC_COUNT}" = "0" ] && echo "  No remoteproc devices found (M7/M33 not configured or driver not loaded)"
fi

# ---------------------------------------------------------------------------
# SECTION: SERVICES
# ---------------------------------------------------------------------------
if should_run "SERVICES"; then
    section_header "SERVICES"

    if command -v systemctl &>/dev/null; then
        ACTIVE_COUNT=$(systemctl list-units --state=active --no-legend 2>/dev/null | wc -l || echo "0")
        FAILED_COUNT=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l || echo "0")
        printf "%-20s: %s\n" "Active services"  "${ACTIVE_COUNT}"
        printf "%-20s: %s\n" "Failed services"  "${FAILED_COUNT}"

        if [ "${FAILED_COUNT}" -gt 0 ]; then
            echo ""
            echo "Failed units:"
            systemctl list-units --state=failed --no-legend 2>/dev/null | \
                awk '{printf "  FAILED: %s\n", $1}' | head -10
        fi
    else
        echo "  systemctl not available"
        # Fall back to counting processes
        PROC_COUNT=$(ls /proc | grep -c '^[0-9]' 2>/dev/null || echo "0")
        printf "%-20s: %s\n" "Running processes" "${PROC_COUNT}"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: DMESG ERRORS
# ---------------------------------------------------------------------------
if should_run "DMESG" && [ "${NO_DMESG}" = "0" ]; then
    section_header "DMESG ERRORS"

    # Last 20 error-level messages
    ERROR_LINES=$(dmesg --notime --level=err 2>/dev/null | tail -20 || \
                  dmesg 2>/dev/null | grep -iE "^\[.*\] \[.*error\|^\[.*\] error" | tail -20 || \
                  echo "")

    if [ -n "${ERROR_LINES}" ]; then
        echo "Last 20 kernel errors:"
        echo "${ERROR_LINES}" | sed 's/^/  /'
    else
        echo "No kernel errors in ring buffer."
    fi

    # Performance-relevant patterns
    echo ""
    echo "Performance-relevant messages:"
    PERF_LINES=$(dmesg --notime 2>/dev/null | \
        grep -iE "throttl|thermal.*trip|oom.kill|out.of.memory|cpufreq.*fail|clk.*fail|regulator.*fail|remoteproc.*crash|hung.task|dma.*error|timeout" \
        | tail -15 || true)

    if [ -n "${PERF_LINES}" ]; then
        echo "${PERF_LINES}" | sed 's/^/  /'
    else
        echo "  None found."
    fi
fi

# ---------------------------------------------------------------------------
# Footer
# ---------------------------------------------------------------------------
if [ "${QUIET}" = "0" ] && [ "${#SECTIONS_FILTER[@]}" -eq 0 ]; then
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "Snapshot complete. Timestamp: ${SNAP_TIME}"
    echo "══════════════════════════════════════════════════════════════"
fi
