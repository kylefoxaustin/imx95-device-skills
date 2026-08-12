#!/bin/bash
# lib/board_detect.sh — detect i.MX 95 board variant at runtime
#
# Exports:
#   BOARD_MODEL   — full model string, e.g. "NXP i.MX95 19x19 EVK board"
#   BOARD_SOC     — SoC identifier, e.g. "i.MX95"
#   BOARD_REV     — SoC/board revision, e.g. "1.1"
#   BOARD_COMPAT  — first compatible string, e.g. "fsl,imx95-19x19-evk"
#   BOARD_VARIANT — short variant tag: "frdm-evk" | "19x19-evk" | "custom" | "unknown"
#
# Usage:
#   source "${SCRIPT_DIR}/../../lib/board_detect.sh"
#   echo "Running on: ${BOARD_MODEL} (${BOARD_VARIANT})"

# Guard against double-sourcing
[[ -n "${_IMX95_BOARD_DETECT_SH_LOADED:-}" ]] && return 0
_IMX95_BOARD_DETECT_SH_LOADED=1

# Ensure common.sh is loaded
if [[ -z "${_IMX95_COMMON_SH_LOADED:-}" ]]; then
    _BD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/common.sh
    source "${_BD_DIR}/common.sh"
fi

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_dt_read() {
    local path="$1"
    local default="${2:-}"
    if [ -f "${path}" ]; then
        # Device tree strings are NUL-terminated; strip NULs
        tr -d '\0' < "${path}" 2>/dev/null || echo "${default}"
    else
        echo "${default}"
    fi
}

_dt_read_compat() {
    # compatible is NUL-separated list; return newline-separated
    local path="$1"
    if [ -f "${path}" ]; then
        tr '\0' '\n' < "${path}" 2>/dev/null | grep -v '^$'
    fi
}

# ---------------------------------------------------------------------------
# Detection logic
# ---------------------------------------------------------------------------

_detect_board() {
    local compat_file="/sys/firmware/devicetree/base/compatible"
    local proc_compat="/proc/device-tree/compatible"
    local model_file="/sys/firmware/devicetree/base/model"
    local soc0_id="/sys/devices/soc0/soc_id"
    local soc0_rev="/sys/devices/soc0/revision"

    # ── Model string ────────────────────────────────────────────────────────
    BOARD_MODEL=$(_dt_read "${model_file}" "unknown")

    # ── SoC ID ──────────────────────────────────────────────────────────────
    if [ -f "${soc0_id}" ]; then
        BOARD_SOC=$(_dt_read "${soc0_id}" "unknown")
    else
        # Fall back: parse from compatible string
        BOARD_SOC="unknown"
        for compat_src in "${compat_file}" "${proc_compat}"; do
            if [ -f "${compat_src}" ]; then
                if tr '\0' '\n' < "${compat_src}" 2>/dev/null | grep -qi "imx95"; then
                    BOARD_SOC="i.MX95"
                    break
                fi
            fi
        done
    fi

    # ── SoC / Board revision ─────────────────────────────────────────────────
    if [ -f "${soc0_rev}" ]; then
        BOARD_REV=$(_dt_read "${soc0_rev}" "unknown")
    else
        BOARD_REV="unknown"
    fi

    # ── First compatible string ──────────────────────────────────────────────
    BOARD_COMPAT="unknown"
    for compat_src in "${compat_file}" "${proc_compat}"; do
        if [ -f "${compat_src}" ]; then
            BOARD_COMPAT=$(_dt_read_compat "${compat_src}" | head -1)
            break
        fi
    done

    # ── Variant classification ───────────────────────────────────────────────
    # Classify based on compatible string and model
    BOARD_VARIANT="unknown"

    local compat_lower
    compat_lower=$(echo "${BOARD_COMPAT}" | tr '[:upper:]' '[:lower:]')
    local model_lower
    model_lower=$(echo "${BOARD_MODEL}" | tr '[:upper:]' '[:lower:]')

    if echo "${compat_lower}" | grep -q "frdm"; then
        BOARD_VARIANT="frdm-evk"
    elif echo "${compat_lower}" | grep -q "19x19"; then
        BOARD_VARIANT="19x19-evk"
    elif echo "${compat_lower}" | grep -q "evk"; then
        BOARD_VARIANT="evk"
    elif echo "${compat_lower}" | grep -q "imx95"; then
        # It's an i.MX 95 board but not a known NXP EVK
        BOARD_VARIANT="custom"
    fi

    # Refine from model string if compatible didn't give us enough
    if [ "${BOARD_VARIANT}" = "unknown" ]; then
        if echo "${model_lower}" | grep -q "frdm"; then
            BOARD_VARIANT="frdm-evk"
        elif echo "${model_lower}" | grep -q "19x19"; then
            BOARD_VARIANT="19x19-evk"
        elif echo "${model_lower}" | grep -q "evk"; then
            BOARD_VARIANT="evk"
        fi
    fi

    log_debug "board_detect: MODEL='${BOARD_MODEL}' SOC='${BOARD_SOC}' REV='${BOARD_REV}' COMPAT='${BOARD_COMPAT}' VARIANT='${BOARD_VARIANT}'"
}

# ---------------------------------------------------------------------------
# Run detection and export variables
# ---------------------------------------------------------------------------
_detect_board

export BOARD_MODEL
export BOARD_SOC
export BOARD_REV
export BOARD_COMPAT
export BOARD_VARIANT

# ---------------------------------------------------------------------------
# Convenience functions
# ---------------------------------------------------------------------------

# board_summary — prints a one-line board summary
board_summary() {
    echo "Board: ${BOARD_MODEL} | SoC: ${BOARD_SOC} rev${BOARD_REV} | Variant: ${BOARD_VARIANT}"
}

# board_is_frdm_evk — returns 0 if this is the FRDM-IMX95 EVK
board_is_frdm_evk() {
    [ "${BOARD_VARIANT}" = "frdm-evk" ]
}

# board_is_19x19_evk — returns 0 if this is the 19x19 EVK
board_is_19x19_evk() {
    [ "${BOARD_VARIANT}" = "19x19-evk" ]
}

# board_assert_imx95 — dies if not an i.MX 95 board
board_assert_imx95() {
    if ! echo "${BOARD_SOC}" | grep -qi "imx95\|i\.mx95"; then
        die "This skill requires an i.MX 95 SoC. Detected: '${BOARD_SOC}' on '${BOARD_MODEL}'"
    fi
}

# board_print_env — prints all exported BOARD_* variables
board_print_env() {
    echo "BOARD_MODEL   = ${BOARD_MODEL}"
    echo "BOARD_SOC     = ${BOARD_SOC}"
    echo "BOARD_REV     = ${BOARD_REV}"
    echo "BOARD_COMPAT  = ${BOARD_COMPAT}"
    echo "BOARD_VARIANT = ${BOARD_VARIANT}"
}
