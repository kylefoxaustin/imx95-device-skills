#!/bin/bash
# skills/imx95-npu-benchmark/scripts/check_eiq.sh
#
# Verifies that the eIQ runtime is installed and the NPU driver is loaded.
# Exports EIQ_DELEGATE_PATH for use by bench_npu.sh.
#
# Exit codes:
#   0 — eIQ and NPU driver both available
#   1 — eIQ delegate not found
#   2 — NPU driver not loaded
#   3 — benchmark_model tool not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/sysfs.sh
source "${REPO_ROOT}/lib/sysfs.sh"

usage() {
    echo "Usage: $(basename "$0") [--quiet]"
    echo "Checks eIQ runtime installation and NPU driver state."
    echo "Exports EIQ_DELEGATE_PATH on success."
}

QUIET=0
[[ "${1:-}" = "--quiet" ]] && QUIET=1
[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage && exit 0

# ---------------------------------------------------------------------------
# Check 1: benchmark_model tool
# ---------------------------------------------------------------------------
BM_PATH=""
for candidate in /usr/bin/benchmark_model /usr/local/bin/benchmark_model \
                 /opt/eiq/bin/benchmark_model; do
    if [ -x "${candidate}" ]; then
        BM_PATH="${candidate}"
        break
    fi
done

if [ -z "${BM_PATH}" ]; then
    [ "${QUIET}" = "0" ] && {
        log_error "benchmark_model not found."
        log_error "Install with: opkg install packagegroup-imx-eiq"
        log_error "  or: apt-get install imx-eiq-toolkit"
        log_error "Searched: /usr/bin, /usr/local/bin, /opt/eiq/bin"
    }
    exit 3
fi
[ "${QUIET}" = "0" ] && log_info "benchmark_model: ${BM_PATH}"

# ---------------------------------------------------------------------------
# Check 2: eIQ Neutron delegate library
# ---------------------------------------------------------------------------
DELEGATE_PATH=""
for lib in \
    /usr/lib/libethosu_delegate.so \
    /usr/lib/libvx_delegate.so \
    /usr/local/lib/libethosu_delegate.so \
    /usr/lib/libNNDelegate.so \
    /usr/lib/aarch64-linux-gnu/libethosu_delegate.so \
    /usr/lib/aarch64-linux-gnu/libvx_delegate.so; do
    if [ -f "${lib}" ]; then
        DELEGATE_PATH="${lib}"
        break
    fi
done

if [ -z "${DELEGATE_PATH}" ]; then
    [ "${QUIET}" = "0" ] && {
        log_error "eIQ Neutron delegate library not found."
        log_error "Searched common paths for libethosu_delegate.so and libvx_delegate.so"
        log_error "NPU inference will fall back to CPU."
        log_error "Install with: opkg install packagegroup-imx-eiq"
    }
    exit 1
fi
[ "${QUIET}" = "0" ] && log_info "eIQ delegate: ${DELEGATE_PATH}"

# Export for use by bench_npu.sh
export EIQ_DELEGATE_PATH="${DELEGATE_PATH}"
export BENCHMARK_MODEL_PATH="${BM_PATH}"

# ---------------------------------------------------------------------------
# Check 3: NPU driver loaded
# ---------------------------------------------------------------------------
NPU_LOADED=0
for path in /sys/bus/platform/drivers/neutron \
            /sys/bus/platform/drivers/ethosu \
            /sys/bus/platform/drivers/imx-neutron; do
    [ -d "${path}" ] && NPU_LOADED=1 && break
done

if [ "${NPU_LOADED}" = "0" ]; then
    for mod in neutron ethosu imx_neutron; do
        lsmod 2>/dev/null | grep -q "^${mod}[[:space:]]" && NPU_LOADED=1 && break
    done
fi

if [ "${NPU_LOADED}" = "0" ]; then
    [ "${QUIET}" = "0" ] && {
        log_warn "NPU driver not detected in /sys/bus/platform/drivers/ or lsmod."
        log_warn "The delegate library exists but the NPU hardware may not be accessible."
        log_warn "Check dmesg for NPU driver errors: dmesg | grep -i neutron"
    }
    exit 2
fi
[ "${QUIET}" = "0" ] && log_info "NPU driver: loaded"

# ---------------------------------------------------------------------------
# Check 4: Python tflite_runtime (optional, for Python-based benchmarks)
# ---------------------------------------------------------------------------
if python3 -c "import tflite_runtime" &>/dev/null 2>&1; then
    TFL_VER=$(python3 -c "import tflite_runtime; print(tflite_runtime.__version__)" 2>/dev/null || echo "unknown")
    [ "${QUIET}" = "0" ] && log_info "tflite_runtime (python3): ${TFL_VER}"
else
    [ "${QUIET}" = "0" ] && log_info "tflite_runtime (python3): not installed (optional)"
fi

[ "${QUIET}" = "0" ] && log_info "eIQ check PASSED — NPU benchmark ready"
exit 0
