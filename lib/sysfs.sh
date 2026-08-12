#!/bin/bash
# lib/sysfs.sh — sysfs helper functions for imx95-device-skills
#
# Provides typed, safe accessors for i.MX 95 sysfs paths.
# All functions return "N/A" (or a numeric 0) when the path is unreadable,
# so callers never need to handle missing-file errors.
#
# Source this file after common.sh:
#   source "${SCRIPT_DIR}/../../lib/common.sh"
#   source "${SCRIPT_DIR}/../../lib/sysfs.sh"

# Guard against double-sourcing
[[ -n "${_IMX95_SYSFS_SH_LOADED:-}" ]] && return 0
_IMX95_SYSFS_SH_LOADED=1

# Ensure common.sh is loaded (provides sysfs_read)
if [[ -z "${_IMX95_COMMON_SH_LOADED:-}" ]]; then
    _SYSFS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/common.sh
    source "${_SYSFS_DIR}/common.sh"
fi

# ---------------------------------------------------------------------------
# CPU frequency helpers
# ---------------------------------------------------------------------------

# cpu_freq_mhz N — returns current frequency of cpu N in MHz
# Example: cpu_freq_mhz 0  →  1800
cpu_freq_mhz() {
    local n="${1:-0}"
    local path="/sys/devices/system/cpu/cpu${n}/cpufreq/scaling_cur_freq"
    local khz
    khz=$(sysfs_read "${path}" "0")
    echo $(( khz / 1000 ))
}

# cpu_max_freq_mhz N — returns scaling_max_freq for cpu N in MHz
cpu_max_freq_mhz() {
    local n="${1:-0}"
    local path="/sys/devices/system/cpu/cpu${n}/cpufreq/scaling_max_freq"
    local khz
    khz=$(sysfs_read "${path}" "0")
    echo $(( khz / 1000 ))
}

# cpu_min_freq_mhz N — returns scaling_min_freq for cpu N in MHz
cpu_min_freq_mhz() {
    local n="${1:-0}"
    local path="/sys/devices/system/cpu/cpu${n}/cpufreq/scaling_min_freq"
    local khz
    khz=$(sysfs_read "${path}" "0")
    echo $(( khz / 1000 ))
}

# cpu_governor N — returns cpufreq governor name for cpu N
cpu_governor() {
    local n="${1:-0}"
    sysfs_read "/sys/devices/system/cpu/cpu${n}/cpufreq/scaling_governor" "unknown"
}

# cpu_online N — returns 1 if cpu N is online, 0 if offline
# cpu0 is always online (no online file); returns 1 for cpu0
cpu_online() {
    local n="${1:-0}"
    if [ "${n}" -eq 0 ]; then
        echo "1"
        return
    fi
    sysfs_read "/sys/devices/system/cpu/cpu${n}/online" "0"
}

# cpu_count_online — returns number of online CPUs
cpu_count_online() {
    local count=0
    for cpu in /sys/devices/system/cpu/cpu[0-9]*/; do
        local n
        n=$(basename "${cpu}" | tr -d 'cpu')
        if [ "$(cpu_online "${n}")" = "1" ]; then
            count=$(( count + 1 ))
        fi
    done
    echo "${count}"
}

# ---------------------------------------------------------------------------
# Thermal helpers
# ---------------------------------------------------------------------------

# cpu_temp_c ZONE — returns temperature of thermal zone ZONE in °C
# ZONE can be a number (0, 1, 2...) or a type string (e.g., "cpu-thermal")
# Example: cpu_temp_c 0  →  45
#          cpu_temp_c cpu-thermal  →  52
cpu_temp_c() {
    local zone="${1:-0}"
    local temp_milli=""

    # If zone is a number, use direct path
    if [[ "${zone}" =~ ^[0-9]+$ ]]; then
        temp_milli=$(sysfs_read "/sys/class/thermal/thermal_zone${zone}/temp" "0")
    else
        # Search by type string
        for z in /sys/class/thermal/thermal_zone*/; do
            local ztype
            ztype=$(sysfs_read "${z}type" "")
            if [ "${ztype}" = "${zone}" ]; then
                temp_milli=$(sysfs_read "${z}temp" "0")
                break
            fi
        done
        temp_milli="${temp_milli:-0}"
    fi

    echo $(( temp_milli / 1000 ))
}

# thermal_zone_type N — returns the type string for thermal zone N
thermal_zone_type() {
    local n="${1:-0}"
    sysfs_read "/sys/class/thermal/thermal_zone${n}/type" "unknown"
}

# thermal_zone_count — returns number of thermal zones present
thermal_zone_count() {
    ls -d /sys/class/thermal/thermal_zone*/ 2>/dev/null | wc -l
}

# max_thermal_temp_c — returns the highest temperature across all thermal zones in °C
max_thermal_temp_c() {
    local max=0
    for zone in /sys/class/thermal/thermal_zone*/; do
        local temp_milli
        temp_milli=$(sysfs_read "${zone}temp" "0")
        local temp_c=$(( temp_milli / 1000 ))
        [ "${temp_c}" -gt "${max}" ] && max="${temp_c}"
    done
    echo "${max}"
}

# ---------------------------------------------------------------------------
# Memory helpers
# ---------------------------------------------------------------------------

# mem_total_mb — returns total RAM in MB from /proc/meminfo
mem_total_mb() {
    awk '/^MemTotal:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# mem_available_mb — returns available RAM in MB from /proc/meminfo
mem_available_mb() {
    awk '/^MemAvailable:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# mem_free_mb — returns free RAM in MB (MemFree, not MemAvailable)
mem_free_mb() {
    awk '/^MemFree:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# mem_cached_mb — returns page cache size in MB
mem_cached_mb() {
    awk '/^Cached:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# cma_total_mb — returns CmaTotal in MB from /proc/meminfo
cma_total_mb() {
    awk '/^CmaTotal:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# cma_free_mb — returns CmaFree in MB from /proc/meminfo
cma_free_mb() {
    awk '/^CmaFree:/{printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo "0"
}

# ---------------------------------------------------------------------------
# GPU helpers (Vivante GC7000UL via devfreq)
# ---------------------------------------------------------------------------

# _find_gpu_devfreq — internal: finds the GPU devfreq sysfs directory
_find_gpu_devfreq() {
    # Try known driver name patterns
    for pattern in "*gpu*" "*gc*" "*vivante*" "*galcore*" "*GC*"; do
        local found
        found=$(ls -d /sys/class/devfreq/${pattern} 2>/dev/null | head -1)
        if [ -n "${found}" ]; then
            echo "${found}"
            return 0
        fi
    done
    # Try by scanning uevent for DRIVER= matching GPU drivers
    for dev in /sys/class/devfreq/*/; do
        local driver
        driver=$(cat "${dev}device/uevent" 2>/dev/null | grep '^DRIVER=' | cut -d= -f2)
        case "${driver}" in
            galcore|vivante|gc*|etnaviv) echo "${dev%/}"; return 0 ;;
        esac
    done
    echo ""
}

# gpu_freq_mhz — returns current GPU frequency in MHz, or 0 if not found
gpu_freq_mhz() {
    local devfreq
    devfreq=$(_find_gpu_devfreq)
    if [ -z "${devfreq}" ]; then
        echo "0"
        return
    fi
    local hz
    hz=$(sysfs_read "${devfreq}/cur_freq" "0")
    echo $(( hz / 1000000 ))
}

# gpu_max_freq_mhz — returns GPU max frequency in MHz
gpu_max_freq_mhz() {
    local devfreq
    devfreq=$(_find_gpu_devfreq)
    [ -z "${devfreq}" ] && echo "0" && return
    local hz
    hz=$(sysfs_read "${devfreq}/max_freq" "0")
    echo $(( hz / 1000000 ))
}

# gpu_governor — returns GPU devfreq governor name
gpu_governor() {
    local devfreq
    devfreq=$(_find_gpu_devfreq)
    [ -z "${devfreq}" ] && echo "N/A" && return
    sysfs_read "${devfreq}/governor" "unknown"
}

# ---------------------------------------------------------------------------
# NPU helpers (eIQ Neutron)
# ---------------------------------------------------------------------------

# npu_state — returns "loaded", "not_loaded", or "unknown"
# Checks platform driver binding and lsmod
npu_state() {
    # Check platform driver directories
    for path in /sys/bus/platform/drivers/neutron \
                /sys/bus/platform/drivers/ethosu \
                /sys/bus/platform/drivers/imx-neutron \
                /sys/bus/platform/drivers/neutron-npu; do
        if [ -d "${path}" ]; then
            echo "loaded"
            return 0
        fi
    done

    # Check lsmod
    if lsmod 2>/dev/null | grep -qE "^(neutron|ethosu|imx_neutron)"; then
        echo "loaded"
        return 0
    fi

    # Check for device node
    if ls /dev/neutron* /dev/ethosu* 2>/dev/null | grep -q .; then
        echo "loaded"
        return 0
    fi

    echo "not_loaded"
}

# npu_driver_path — returns the sysfs path of the NPU driver, or empty string
npu_driver_path() {
    for path in /sys/bus/platform/drivers/neutron \
                /sys/bus/platform/drivers/ethosu \
                /sys/bus/platform/drivers/imx-neutron; do
        [ -d "${path}" ] && echo "${path}" && return 0
    done
    echo ""
}

# eiq_delegate_path — returns path to eIQ TFLite delegate .so, or empty string
eiq_delegate_path() {
    for lib in /usr/lib/libethosu_delegate.so \
               /usr/lib/libvx_delegate.so \
               /usr/local/lib/libethosu_delegate.so \
               /usr/lib/libNNDelegate.so \
               /usr/lib/aarch64-linux-gnu/libethosu_delegate.so; do
        [ -f "${lib}" ] && echo "${lib}" && return 0
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Board identity helpers
# ---------------------------------------------------------------------------

# get_board_rev — returns board revision string from sysfs or device tree
get_board_rev() {
    # Try soc0 first
    local rev
    rev=$(sysfs_read "/sys/devices/soc0/revision" "")
    [ -n "${rev}" ] && echo "${rev}" && return

    # Try device tree board revision property
    local dt_rev="/sys/firmware/devicetree/base/board-rev"
    [ -f "${dt_rev}" ] && cat "${dt_rev}" 2>/dev/null | tr -d '\0' && return

    echo "unknown"
}

# get_soc_rev — returns SoC revision (e.g., "1.1") from /sys/devices/soc0/revision
get_soc_rev() {
    sysfs_read "/sys/devices/soc0/revision" "unknown"
}

# get_soc_id — returns SoC ID string (e.g., "i.MX95") from /sys/devices/soc0/soc_id
get_soc_id() {
    sysfs_read "/sys/devices/soc0/soc_id" "unknown"
}

# get_board_model — returns full board model string from device tree
get_board_model() {
    local model_file="/sys/firmware/devicetree/base/model"
    if [ -f "${model_file}" ]; then
        cat "${model_file}" 2>/dev/null | tr -d '\0'
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Remoteproc helpers (M7 / M33)
# ---------------------------------------------------------------------------

# remoteproc_state NAME — returns state of a remoteproc by name substring
# Example: remoteproc_state m7  →  running
remoteproc_state() {
    local name_pattern="${1:-}"
    for rp in /sys/bus/remoteproc/devices/remoteproc*/; do
        local rp_name
        rp_name=$(sysfs_read "${rp}name" "")
        if echo "${rp_name}" | grep -qi "${name_pattern}"; then
            sysfs_read "${rp}state" "unknown"
            return 0
        fi
    done
    echo "not_found"
}

# ---------------------------------------------------------------------------
# Storage helpers
# ---------------------------------------------------------------------------

# rootfs_type — returns "ro" or "rw" based on mount flags for /
rootfs_type() {
    if mount | grep -E "^[^ ]+ on / " | grep -q '\bro\b'; then
        echo "ro"
    else
        echo "rw"
    fi
}

# emmc_size_gb — returns eMMC size in GB by reading the block device size
emmc_size_gb() {
    local size_sectors
    # mmcblk0 is typically the eMMC on i.MX 95
    for dev in mmcblk0 mmcblk1; do
        local size_file="/sys/block/${dev}/size"
        if [ -f "${size_file}" ]; then
            size_sectors=$(cat "${size_file}" 2>/dev/null || echo "0")
            # Each sector is 512 bytes
            echo $(( size_sectors * 512 / 1024 / 1024 / 1024 ))
            return
        fi
    done
    echo "0"
}
