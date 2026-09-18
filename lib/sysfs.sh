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

# max_thermal_temp_c — highest temperature across all thermal zones, in °C.
#   Prints EMPTY (and returns 1) if no zone could be read.
#
#   ⚠️ It used to print its accumulator default of 0 in that case. A caller then
#   recorded "0 C" as a MEASURED start temperature and its "temperature unknown"
#   branch never fired, because "0" is not empty. A sensor that reports a
#   plausible value when it read nothing is worse than one that reports nothing:
#   0 °C is in range, so nothing downstream can tell it apart from a cold board.
max_thermal_temp_c() {
    local max="" temp_milli temp_c
    for zone in /sys/class/thermal/thermal_zone*/; do
        [ -r "${zone}temp" ] || continue
        temp_milli=$(sysfs_read "${zone}temp" "")
        [ -n "${temp_milli}" ] || continue
        case "${temp_milli}" in *[!0-9-]*) continue ;; esac
        temp_c=$(( temp_milli / 1000 ))
        if [ -z "${max}" ] || [ "${temp_c}" -gt "${max}" ]; then max="${temp_c}"; fi
    done
    [ -n "${max}" ] || return 1
    echo "${max}"
}

# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ DO NOT GATE A BENCHMARK ON max_thermal_temp_c. USE thermal_min_margin_c.
#
# MEASURED on this board, 2026-08-12, idle at loadavg 0.06:
#     thermal_zone0  ana-thermal   51 °C   passive trip 105 °C
#     thermal_zone1  a55-thermal   52 °C   passive trip 105 °C
#     thermal_zone2  pf09         105 °C   passive trip 140 °C   <- PMIC
#     thermal_zone3  pf53_soc     105 °C   passive trip 140 °C   <- PMIC
#     thermal_zone4  pf53_arm     105 °C   passive trip 140 °C   <- PMIC
#
# The three PMIC regulator zones report a FLAT 105000 m°C constant. It is not a
# temperature — it does not move, and it sits 35 °C below its own passive trip.
# The SoC is at 52 °C.
#
# A max-across-zones compared to a hardcoded 80 °C therefore refuses EVERY run on
# a stone-cold board. That is what happened the first time this gate met real
# silicon. The failure is safe (it refuses rather than measuring hot), but a gate
# that always refuses gets deleted by the next person, and then nothing is gated.
#
# The fix is to stop comparing absolute temperatures to a constant we invented,
# and instead ask each zone how close it is to ITS OWN trip point — which is the
# only threshold the hardware actually asserts. No zone-name allowlist needed:
# the PMIC placeholder self-excludes because 105 against a 140 trip is a 35 °C
# margin, while a genuinely hot A55 at 100 against its 105 trip is a 5 °C margin.
# ─────────────────────────────────────────────────────────────────────────────

# thermal_min_margin_c — smallest (passive-trip − current) across all zones, in °C.
#
#   PRINTS: "<margin> <zone-type>"  — both on stdout, space-separated.
#   Returns 1 and prints nothing if no zone with a usable trip could be read.
#
#   ⚠️ It does NOT set a global for the zone name, and that is deliberate. It used
#   to, and callers do `MARGIN="$(thermal_min_margin_c)"` — a COMMAND SUBSTITUTION,
#   which runs in a subshell, so the global died with the subshell and the report
#   printed `to '' trip`. Caught on silicon. A function whose output is consumed by
#   `$( )` can only communicate on stdout; anything else silently evaporates.
#   Callers: read both fields, e.g.
#       read -r MARGIN ZONE <<<"$(thermal_min_margin_c)"
thermal_min_margin_c() {
    local min="" minzone="" zone ztype temp trip tripty margin
    for zone in /sys/class/thermal/thermal_zone*/; do
        [ -r "${zone}temp" ] || continue
        temp=$(sysfs_read "${zone}temp" "")
        case "${temp}" in ''|*[!0-9-]*) continue ;; esac
        ztype=$(sysfs_read "${zone}type" "unknown")

        # Prefer the lowest passive/hot trip; fall back to critical.
        trip=""
        for tp in "${zone}"trip_point_*_temp; do
            [ -f "${tp}" ] || continue
            tripty=$(sysfs_read "${tp%_temp}_type" "")
            case "${tripty}" in passive|hot|active) ;; *) continue ;; esac
            local v; v=$(sysfs_read "${tp}" "")
            case "${v}" in ''|*[!0-9-]*) continue ;; esac
            # A trip <= 0 is an UNSET trip, not a 0 °C limit. Some drivers park
            # unset trips at INT_MIN (seen on a host's iwlwifi zone: margin came
            # out as -2147519, which would refuse every run forever). Ignore them.
            [ "${v}" -gt 0 ] || continue
            if [ -z "${trip}" ] || [ "${v}" -lt "${trip}" ]; then trip="${v}"; fi
        done
        if [ -z "${trip}" ]; then
            for tp in "${zone}"trip_point_*_temp; do
                [ -f "${tp}" ] || continue
                local v; v=$(sysfs_read "${tp}" "")
                case "${v}" in ''|*[!0-9-]*) continue ;; esac
                [ "${v}" -gt 0 ] || continue
                if [ -z "${trip}" ] || [ "${v}" -lt "${trip}" ]; then trip="${v}"; fi
            done
        fi
        [ -n "${trip}" ] || continue

        margin=$(( (trip - temp) / 1000 ))
        if [ -z "${min}" ] || [ "${margin}" -lt "${min}" ]; then
            min="${margin}"; minzone="${ztype}"
        fi
    done
    [ -n "${min}" ] || return 1
    echo "${min} ${minzone}"
}

# soc_thermal_temp_c — the SoC/CPU temperature, ignoring PMIC zones.
#   For REPORTING a meaningful number. Gating still uses the margin above.
soc_thermal_temp_c() {
    local best="" zone ztype temp
    for zone in /sys/class/thermal/thermal_zone*/; do
        ztype=$(sysfs_read "${zone}type" "")
        case "${ztype}" in
            *a55*|*cpu*|*soc-thermal*|*ana*) ;;
            *) continue ;;
        esac
        temp=$(sysfs_read "${zone}temp" "")
        case "${temp}" in ''|*[!0-9-]*) continue ;; esac
        temp=$(( temp / 1000 ))
        if [ -z "${best}" ] || [ "${temp}" -gt "${best}" ]; then best="${temp}"; fi
    done
    [ -n "${best}" ] || return 1
    echo "${best}"
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
# GPU helpers — Arm Mali-G310 (1 core, r0p0) via devfreq
#
# ⚠️ NOT a Vivante GC7000UL. That is the i.MX8M Plus GPU, and it was named here
# in the first version of this file — the same wrong-neighbouring-SoC drift as
# the delegate bug, sitting one screen above it. Ground truth §1.1.
#
# ⚠️ AND THE GPU IS NOT AN ML TARGET ON THIS BOARD. Mali-G310 is graphics only:
# OpenCL is an ICD stub (libOpenCLDriverStub.so) — there is no GPGPU compute
# path. Do not offer it as an inference backend. [MEASURED]
#
# The vivante/galcore/etnaviv patterns below are retained ONLY as a fallback for
# other i.MX parts a portable skill might touch; on this board the match should
# come from the *gpu*/mali patterns.
# ---------------------------------------------------------------------------

# _find_gpu_devfreq — internal: finds the GPU devfreq sysfs directory
_find_gpu_devfreq() {
    # Try known driver name patterns (mali first — this board is Mali-G310)
    for pattern in "*mali*" "*gpu*" "*gc*" "*vivante*" "*galcore*" "*GC*"; do
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
            mali*|panfrost|galcore|vivante|gc*|etnaviv) echo "${dev%/}"; return 0 ;;
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

# ⚠️ DO NOT ADD ethosu / vx PATHS TO ANYTHING BELOW.
#
# The first version of this file searched for libethosu_delegate.so (Arm Ethos-U65
# = the i.MX93 NPU) and libvx_delegate.so (VeriSilicon VX = the i.MX8M Plus NPU),
# and matched whichever it found first. Both are real NXP delegates. Neither is
# this SoC's. A "search a list of plausible paths" helper is not robustness here —
# it is a mechanism for binding to the wrong accelerator and reporting success.
# i.MX95 has exactly ONE delegate. See references/imx95-ground-truth.md §1.1.

# npu_state — "present" or "absent".
#   ⚠️ PRESENCE, NOT AVAILABILITY. This says the Neutron driver bound. It says
#   NOTHING about whether another tenant is using the NPU right now. Do not build
#   an "is the NPU free?" check on this — see ground-truth §3.1 for why an
#   occupancy claim that cannot be substantiated must refuse rather than guess.
npu_state() {
    for path in /sys/bus/platform/drivers/neutron \
                /sys/bus/platform/drivers/imx-neutron \
                /sys/bus/platform/drivers/neutron-npu; do
        [ -d "${path}" ] && { echo "present"; return 0; }
    done

    lsmod 2>/dev/null | grep -qE "^(neutron|imx_neutron)" && { echo "present"; return 0; }

    [ -e /dev/neutron0 ] && { echo "present"; return 0; }

    echo "absent"
}

# npu_driver_path — sysfs path of the Neutron driver, or empty string
npu_driver_path() {
    for path in /sys/bus/platform/drivers/neutron \
                /sys/bus/platform/drivers/imx-neutron \
                /sys/bus/platform/drivers/neutron-npu; do
        [ -d "${path}" ] && { echo "${path}"; return 0; }
    done
    echo ""
}

# eiq_delegate_path — the i.MX95 Neutron TFLite delegate, or empty string.
#   Empty means "not present". It does NOT mean "use something else".
#   Callers MUST treat empty as a refusal — lib/neutron.sh:neutron_require_delegate
#   is the supported way to gate on this.
eiq_delegate_path() {
    local lib="${IMX95_NEUTRON_DELEGATE:-/usr/lib/libneutron_delegate.so}"
    [ -r "${lib}" ] && { echo "${lib}"; return 0; }
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
