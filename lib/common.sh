#!/bin/bash
# lib/common.sh — shared shell helpers for imx95-device-skills
#
# Source this file at the top of every skill script:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"
#   -- or from skills/<name>/scripts/ --
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../../lib/common.sh"
#
# Provides: log_info, log_warn, log_error, log_debug, log_section,
#           require_root, require_tool, board_is_imx95, thermal_ok,
#           confirm_destructive, die, indent

# Guard against double-sourcing
[[ -n "${_IMX95_COMMON_SH_LOADED:-}" ]] && return 0
_IMX95_COMMON_SH_LOADED=1

# ---------------------------------------------------------------------------
# Colour support — disabled automatically when stdout is not a tty
# ---------------------------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-0}" != "1" ]; then
    _C_RED='\033[0;31m'
    _C_YELLOW='\033[1;33m'
    _C_GREEN='\033[0;32m'
    _C_CYAN='\033[0;36m'
    _C_BLUE='\033[0;34m'
    _C_BOLD='\033[1m'
    _C_DIM='\033[2m'
    _C_RESET='\033[0m'
else
    _C_RED='' _C_YELLOW='' _C_GREEN='' _C_CYAN=''
    _C_BLUE='' _C_BOLD='' _C_DIM='' _C_RESET=''
fi

# ---------------------------------------------------------------------------
# Logging functions
# ---------------------------------------------------------------------------

# log_info MESSAGE — informational, green [INFO] prefix
log_info() {
    echo -e "${_C_GREEN}[INFO]${_C_RESET}  $*"
}

# log_warn MESSAGE — warning, yellow [WARN] prefix, goes to stderr
log_warn() {
    echo -e "${_C_YELLOW}[WARN]${_C_RESET}  $*" >&2
}

# log_error MESSAGE — error, red [ERROR] prefix, goes to stderr
log_error() {
    echo -e "${_C_RED}[ERROR]${_C_RESET} $*" >&2
}

# log_debug MESSAGE — only printed when IMX95_DEBUG=1
log_debug() {
    if [ "${IMX95_DEBUG:-0}" = "1" ]; then
        echo -e "${_C_DIM}[DEBUG]${_C_RESET} $*" >&2
    fi
}

# log_section TITLE — prints a bold section header separator
log_section() {
    local title="$*"
    local line
    line=$(printf '=%.0s' $(seq 1 60))
    echo ""
    echo -e "${_C_BOLD}${_C_CYAN}=== ${title} ===${_C_RESET}"
}

# die MESSAGE [EXIT_CODE] — log error and exit
die() {
    local msg="${1:-Fatal error}"
    local code="${2:-1}"
    log_error "${msg}"
    exit "${code}"
}

# indent — pipe helper: indent stdin by 4 spaces
indent() {
    sed 's/^/    /'
}

# ---------------------------------------------------------------------------
# Privilege check
# ---------------------------------------------------------------------------

# require_root — exits with error if not running as root (UID 0)
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root. Try: sudo $0" 2
    fi
}

# ---------------------------------------------------------------------------
# Tool availability checks
# ---------------------------------------------------------------------------

# require_tool TOOL [INSTALL_HINT] — exits if TOOL is not in PATH
# Example: require_tool gpioinfo "Install with: apt-get install gpiod"
require_tool() {
    local tool="$1"
    local hint="${2:-}"
    if ! command -v "${tool}" &>/dev/null; then
        log_error "Required tool '${tool}' not found in PATH."
        if [ -n "${hint}" ]; then
            log_error "  ${hint}"
        fi
        exit 127
    fi
    log_debug "Tool '${tool}' found at: $(command -v "${tool}")"
}

# require_file PATH [DESCRIPTION] — exits if file/dir does not exist
require_file() {
    local path="$1"
    local desc="${2:-${path}}"
    if [ ! -e "${path}" ]; then
        die "Required path not found: ${desc} (${path})"
    fi
}

# ---------------------------------------------------------------------------
# Board identity check
# ---------------------------------------------------------------------------

# board_is_imx95 — returns 0 (true) if running on an i.MX 95 board,
#                  returns 1 (false) otherwise.
# Checks /sys/firmware/devicetree/base/compatible for "imx95".
board_is_imx95() {
    local compat_file="/sys/firmware/devicetree/base/compatible"
    local proc_compat="/proc/device-tree/compatible"

    # Try sysfs first, fall back to procfs
    local src=""
    if [ -f "${compat_file}" ]; then
        src="${compat_file}"
    elif [ -f "${proc_compat}" ]; then
        src="${proc_compat}"
    else
        log_debug "board_is_imx95: no compatible file found"
        return 1
    fi

    # compatible is NUL-separated; grep for imx95
    if tr '\0' '\n' < "${src}" 2>/dev/null | grep -qi "imx95"; then
        return 0
    else
        return 1
    fi
}

# assert_board_is_imx95 — calls board_is_imx95 and dies if not i.MX 95
assert_board_is_imx95() {
    if ! board_is_imx95; then
        local compat=""
        if [ -f "/sys/firmware/devicetree/base/compatible" ]; then
            compat=$(tr '\0' '\n' < /sys/firmware/devicetree/base/compatible 2>/dev/null | head -1)
        fi
        die "This script requires an i.MX 95 board. Detected: '${compat:-unknown}'"
    fi
    log_debug "Board identity confirmed: i.MX 95"
}

# ---------------------------------------------------------------------------
# Thermal safety gate
# ---------------------------------------------------------------------------

# thermal_ok [MAX_TEMP_C] — returns 0 if ALL thermal zones are below MAX_TEMP_C
#                           returns 1 if any zone is at or above the threshold.
# Default threshold: 80°C (conservative — throttling typically starts at 85°C on i.MX 95)
#
# Usage before starting heavy workloads:
#   if ! thermal_ok; then
#       log_warn "Board is too hot to start benchmark. Waiting..."
#   fi
thermal_ok() {
    local max_temp_c="${1:-80}"
    local max_temp_milli=$(( max_temp_c * 1000 ))
    local zone_dir="/sys/class/thermal"
    local all_ok=0

    if [ ! -d "${zone_dir}" ]; then
        log_debug "thermal_ok: ${zone_dir} not found — assuming OK"
        return 0
    fi

    for zone in "${zone_dir}"/thermal_zone*/; do
        local temp_file="${zone}temp"
        [ -f "${temp_file}" ] || continue

        local temp_milli
        temp_milli=$(cat "${temp_file}" 2>/dev/null || echo "0")
        local temp_c=$(( temp_milli / 1000 ))

        if [ "${temp_milli}" -ge "${max_temp_milli}" ]; then
            local zone_name
            zone_name=$(cat "${zone}type" 2>/dev/null || basename "${zone}")
            log_warn "Thermal zone '${zone_name}' is ${temp_c}°C — at or above ${max_temp_c}°C threshold"
            all_ok=1
        fi
    done

    return "${all_ok}"
}

# wait_for_thermal_ok [MAX_TEMP_C] [TIMEOUT_SECS] — blocks until thermal_ok or timeout
wait_for_thermal_ok() {
    local max_temp_c="${1:-80}"
    local timeout_secs="${2:-120}"
    local elapsed=0
    local interval=5

    while ! thermal_ok "${max_temp_c}"; do
        if [ "${elapsed}" -ge "${timeout_secs}" ]; then
            log_error "Thermal timeout: board did not cool below ${max_temp_c}°C within ${timeout_secs}s"
            return 1
        fi
        log_warn "Waiting for board to cool below ${max_temp_c}°C... (${elapsed}s / ${timeout_secs}s)"
        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
    done
    return 0
}

# ---------------------------------------------------------------------------
# Destructive action confirmation
# ---------------------------------------------------------------------------

# confirm_destructive DESCRIPTION — prints a warning banner and requires the
# user to type exactly "YES" (uppercase) to proceed. Exits 1 on anything else.
#
# Usage:
#   confirm_destructive "This will disable the display manager and modify /boot/cmdline.txt"
confirm_destructive() {
    local description="${1:-This action will modify persistent board state.}"

    echo ""
    echo -e "${_C_RED}${_C_BOLD}╔══════════════════════════════════════════════════════════╗${_C_RESET}"
    echo -e "${_C_RED}${_C_BOLD}║  ⚠  DESTRUCTIVE ACTION — REQUIRES CONFIRMATION           ║${_C_RESET}"
    echo -e "${_C_RED}${_C_BOLD}╚══════════════════════════════════════════════════════════╝${_C_RESET}"
    echo ""
    echo -e "${_C_YELLOW}  ${description}${_C_RESET}"
    echo ""
    echo -e "${_C_BOLD}  This action modifies persistent board state and may require${_C_RESET}"
    echo -e "${_C_BOLD}  a reboot to take effect or to reverse.${_C_RESET}"
    echo ""
    echo -n "  Type YES (uppercase) to proceed, or anything else to abort: "

    local answer
    read -r answer

    if [ "${answer}" != "YES" ]; then
        log_info "Aborted by user."
        exit 0
    fi

    log_info "Confirmed. Proceeding..."
    echo ""
}

# ---------------------------------------------------------------------------
# Debugfs helper
# ---------------------------------------------------------------------------

# ensure_debugfs_mounted — mounts debugfs at /sys/kernel/debug if not already mounted
ensure_debugfs_mounted() {
    if ! mountpoint -q /sys/kernel/debug 2>/dev/null; then
        log_info "Mounting debugfs at /sys/kernel/debug..."
        mount -t debugfs none /sys/kernel/debug || \
            log_warn "Could not mount debugfs — some memory stats may be unavailable"
    fi
}

# ---------------------------------------------------------------------------
# Misc utilities
# ---------------------------------------------------------------------------

# timestamp — prints current UTC timestamp in ISO-8601 format
timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# human_bytes BYTES — converts bytes to human-readable string (KB/MB/GB)
human_bytes() {
    local bytes="${1:-0}"
    if   [ "${bytes}" -ge 1073741824 ]; then
        echo "$(( bytes / 1073741824 )) GB"
    elif [ "${bytes}" -ge 1048576 ]; then
        echo "$(( bytes / 1048576 )) MB"
    elif [ "${bytes}" -ge 1024 ]; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "${bytes} B"
    fi
}

# sysfs_read PATH [DEFAULT] — reads a sysfs file, returns DEFAULT if not readable
sysfs_read() {
    local path="$1"
    local default="${2:-N/A}"
    if [ -r "${path}" ]; then
        cat "${path}" 2>/dev/null || echo "${default}"
    else
        echo "${default}"
    fi
}
