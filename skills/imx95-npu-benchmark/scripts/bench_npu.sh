#!/bin/bash
# skills/imx95-npu-benchmark/scripts/bench_npu.sh
#
# Runs TFLite benchmark_model on MobileNetV2 using the eIQ Neutron NPU delegate.
# Downloads the model if not cached. Reports latency, throughput, and TOPS estimate.
# Checks thermal state before and after the run.
#
# Usage: bench_npu.sh [--model PATH] [--runs N] [--warmup N] [--no-download]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/sysfs.sh
source "${REPO_ROOT}/lib/sysfs.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --model PATH      Path to .tflite model (default: MobileNetV2, auto-downloaded)
  --runs N          Number of benchmark runs (default: 50)
  --warmup N        Number of warmup runs (default: 5)
  --no-download     Do not attempt to download model if missing
  --cpu-fallback    Allow CPU fallback if NPU delegate fails (for comparison)
  -h, --help        Show this help

Environment:
  EIQ_DELEGATE_PATH   Override delegate library path
  BENCHMARK_MODEL_PATH Override benchmark_model binary path
EOF
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODEL_PATH=""
NUM_RUNS=50
NUM_WARMUP=5
NO_DOWNLOAD=0
CPU_FALLBACK=0

# MobileNetV2 1.0 224x224 float32 — standard benchmark model
MODEL_URL="https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v2_1.0_224.tflite"
MODEL_CACHE="/tmp/mobilenet_v2_1.0_224.tflite"
# MobileNetV2 MACs (multiply-accumulate operations) for TOPS calculation
MODEL_MACS=300000000  # ~300M MACs for MobileNetV2 224x224

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)        MODEL_PATH="$2"; shift 2 ;;
        --runs)         NUM_RUNS="$2"; shift 2 ;;
        --warmup)       NUM_WARMUP="$2"; shift 2 ;;
        --no-download)  NO_DOWNLOAD=1; shift ;;
        --cpu-fallback) CPU_FALLBACK=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Step 1: Verify eIQ and NPU
# ---------------------------------------------------------------------------
log_info "Checking eIQ installation..."
if ! bash "${SCRIPT_DIR}/check_eiq.sh" --quiet; then
    EXIT_CODE=$?
    log_error "eIQ check failed (exit code ${EXIT_CODE}). Run check_eiq.sh for details."
    if [ "${CPU_FALLBACK}" = "0" ]; then
        exit "${EXIT_CODE}"
    fi
    log_warn "Proceeding with CPU fallback (--cpu-fallback specified)"
fi

# Resolve paths (may have been exported by check_eiq.sh)
DELEGATE_PATH="${EIQ_DELEGATE_PATH:-}"
BM_PATH="${BENCHMARK_MODEL_PATH:-}"

# Re-resolve if not exported
if [ -z "${BM_PATH}" ]; then
    for candidate in /usr/bin/benchmark_model /usr/local/bin/benchmark_model; do
        [ -x "${candidate}" ] && BM_PATH="${candidate}" && break
    done
fi
[ -z "${BM_PATH}" ] && die "benchmark_model not found"

if [ -z "${DELEGATE_PATH}" ]; then
    for lib in /usr/lib/libethosu_delegate.so /usr/lib/libvx_delegate.so \
               /usr/local/lib/libethosu_delegate.so; do
        [ -f "${lib}" ] && DELEGATE_PATH="${lib}" && break
    done
fi

# ---------------------------------------------------------------------------
# Step 2: Resolve model path
# ---------------------------------------------------------------------------
if [ -z "${MODEL_PATH}" ]; then
    if [ -f "${MODEL_CACHE}" ]; then
        MODEL_PATH="${MODEL_CACHE}"
        log_info "Using cached model: ${MODEL_PATH}"
    elif [ "${NO_DOWNLOAD}" = "0" ]; then
        log_info "Downloading MobileNetV2 model..."
        if command -v wget &>/dev/null; then
            wget -q -O "${MODEL_CACHE}" "${MODEL_URL}" || \
                die "Failed to download model from ${MODEL_URL}"
        elif command -v curl &>/dev/null; then
            curl -s -o "${MODEL_CACHE}" "${MODEL_URL}" || \
                die "Failed to download model from ${MODEL_URL}"
        else
            die "Neither wget nor curl found. Cannot download model. Use --model to specify a local path."
        fi
        MODEL_PATH="${MODEL_CACHE}"
        log_info "Model downloaded to: ${MODEL_PATH}"
    else
        die "Model not found at ${MODEL_CACHE} and --no-download specified. Use --model PATH."
    fi
fi

[ -f "${MODEL_PATH}" ] || die "Model file not found: ${MODEL_PATH}"
MODEL_SIZE_KB=$(du -k "${MODEL_PATH}" | awk '{print $1}')
log_info "Model: ${MODEL_PATH} (${MODEL_SIZE_KB} KB)"

# ---------------------------------------------------------------------------
# Step 3: Thermal check before benchmark
# ---------------------------------------------------------------------------
log_info "Checking thermal state before benchmark..."
TEMP_BEFORE=$(max_thermal_temp_c)
log_info "Max thermal zone temperature: ${TEMP_BEFORE}°C"

if ! thermal_ok 75; then
    log_warn "Board is warm (${TEMP_BEFORE}°C). Waiting up to 60s for cooling..."
    if ! wait_for_thermal_ok 75 60; then
        log_warn "Board did not cool below 75°C. Results may be affected by throttling."
    fi
    TEMP_BEFORE=$(max_thermal_temp_c)
fi

# ---------------------------------------------------------------------------
# Step 4: Build benchmark_model command
# ---------------------------------------------------------------------------
BM_ARGS=(
    "--graph=${MODEL_PATH}"
    "--use_nnapi=false"
    "--use_xnnpack=false"
    "--num_runs=${NUM_RUNS}"
    "--warmup_runs=${NUM_WARMUP}"
    "--min_secs=0"
)

if [ -n "${DELEGATE_PATH}" ]; then
    BM_ARGS+=("--external_delegate_path=${DELEGATE_PATH}")
    BACKEND_DESC="TFLite + eIQ Neutron delegate (${DELEGATE_PATH})"
else
    BACKEND_DESC="TFLite CPU (no NPU delegate found)"
    log_warn "Running on CPU — NPU delegate not available"
fi

# ---------------------------------------------------------------------------
# Step 5: Run benchmark
# ---------------------------------------------------------------------------
echo ""
echo "=== eIQ NPU BENCHMARK ==="
printf "%-14s: %s\n" "Model"    "$(basename "${MODEL_PATH}")"
printf "%-14s: %s\n" "Backend"  "${BACKEND_DESC}"
printf "%-14s: %d  (%d warmup)\n" "Runs" "${NUM_RUNS}" "${NUM_WARMUP}"
printf "%-14s: %d°C\n" "Temp before" "${TEMP_BEFORE}"
echo ""
log_info "Running benchmark (this may take 30–120 seconds)..."

# Capture output
BM_OUTPUT=$("${BM_PATH}" "${BM_ARGS[@]}" 2>&1) || {
    log_error "benchmark_model failed. Output:"
    echo "${BM_OUTPUT}" | tail -20
    exit 1
}

# ---------------------------------------------------------------------------
# Step 6: Parse results
# ---------------------------------------------------------------------------
# benchmark_model output format (relevant lines):
#   Loaded delegate from /usr/lib/libethosu_delegate.so
#   Average inference timings in us: Warmup: NNNN, Init: NNNN, Inference: NNNN
#   count=50 first=NNNN curr=NNNN min=NNNN max=NNNN avg=NNNN std=NNNN

DELEGATE_LOADED=0
echo "${BM_OUTPUT}" | grep -qi "loaded delegate" && DELEGATE_LOADED=1

# Extract timing values (in microseconds)
AVG_US=$(echo "${BM_OUTPUT}" | grep -oP 'avg=\K[0-9]+' | tail -1 || echo "0")
MIN_US=$(echo "${BM_OUTPUT}" | grep -oP 'min=\K[0-9]+' | tail -1 || echo "0")
MAX_US=$(echo "${BM_OUTPUT}" | grep -oP 'max=\K[0-9]+' | tail -1 || echo "0")
STD_US=$(echo "${BM_OUTPUT}" | grep -oP 'std=\K[0-9]+' | tail -1 || echo "0")

# Also try "Inference:" format
if [ "${AVG_US}" = "0" ]; then
    AVG_US=$(echo "${BM_OUTPUT}" | grep -oP 'Inference:\s*\K[0-9]+' | tail -1 || echo "0")
fi

# Convert to ms (2 decimal places via awk)
AVG_MS=$(awk "BEGIN{printf \"%.2f\", ${AVG_US}/1000}")
MIN_MS=$(awk "BEGIN{printf \"%.2f\", ${MIN_US}/1000}")
MAX_MS=$(awk "BEGIN{printf \"%.2f\", ${MAX_US}/1000}")
STD_MS=$(awk "BEGIN{printf \"%.2f\", ${STD_US}/1000}")

# Throughput (inferences per second)
THROUGHPUT=0
[ "${AVG_US}" -gt 0 ] && THROUGHPUT=$(awk "BEGIN{printf \"%.0f\", 1000000/${AVG_US}}")

# TOPS estimate: (MACs * 2 * throughput) / 1e12
TOPS_EST="N/A"
if [ "${THROUGHPUT}" -gt 0 ]; then
    TOPS_EST=$(awk "BEGIN{printf \"%.3f\", (${MODEL_MACS} * 2 * ${THROUGHPUT}) / 1e12}")
fi

# Thermal after
TEMP_AFTER=$(max_thermal_temp_c)
TEMP_DELTA=$(( TEMP_AFTER - TEMP_BEFORE ))

# ---------------------------------------------------------------------------
# Step 7: Print results
# ---------------------------------------------------------------------------
echo "--- Results ---"
printf "%-16s: %s ms\n" "Avg latency"  "${AVG_MS}"
printf "%-16s: %s ms\n" "Min latency"  "${MIN_MS}"
printf "%-16s: %s ms\n" "Max latency"  "${MAX_MS}"
printf "%-16s: %s ms\n" "Std dev"      "${STD_MS}"
printf "%-16s: %s inferences/sec\n" "Throughput" "${THROUGHPUT}"
printf "%-16s: %s TOPS  (based on ~%dM MACs for %s)\n" \
    "Est. TOPS" "${TOPS_EST}" "$(( MODEL_MACS / 1000000 ))" "$(basename "${MODEL_PATH}")"

echo ""
echo "--- Thermal ---"
printf "%-16s: %d°C\n" "Temp before"  "${TEMP_BEFORE}"
printf "%-16s: %d°C  (+%d°C)\n" "Temp after" "${TEMP_AFTER}" "${TEMP_DELTA}"
[ "${TEMP_DELTA}" -ge 15 ] && \
    log_warn "Temperature rose ${TEMP_DELTA}°C during benchmark — results may be affected by throttling"

echo ""
echo "--- Assessment ---"
if [ "${DELEGATE_LOADED}" = "1" ]; then
    echo "NPU delegate : ACTIVE (inference ran on NPU)"
else
    log_warn "NPU delegate : NOT LOADED — inference ran on CPU"
    log_warn "  Check: bash skills/imx95-npu-benchmark/scripts/check_eiq.sh"
    log_warn "  Verify NPU driver: lsmod | grep neutron"
fi

# Performance assessment for MobileNetV2
if [ "${DELEGATE_LOADED}" = "1" ] && [ "${AVG_US}" -gt 0 ]; then
    if   [ "${AVG_US}" -lt 5000 ]; then
        echo "Performance  : EXCELLENT (< 5ms avg)"
    elif [ "${AVG_US}" -lt 10000 ]; then
        echo "Performance  : GOOD (5–10ms avg)"
    elif [ "${AVG_US}" -lt 20000 ]; then
        echo "Performance  : ACCEPTABLE (10–20ms avg)"
    else
        echo "Performance  : SLOW (> 20ms avg) — check thermal throttling and NPU driver"
    fi
fi

echo ""
log_info "Benchmark complete."
