#!/usr/bin/env bash
# skills/imx95-npu-benchmark/scripts/bench_npu.sh
#
# Benchmark a model on the eIQ Neutron — with placement as the gate.
#
# WHAT THIS SCRIPT WILL NOT DO, AND WHY
#
#   * It will not auto-download a float32 MobileNetV2 and call the result an NPU
#     number. The previous version did. A float model is not runnable on the
#     Neutron at all: the delegate path is int8, and the model must additionally
#     be compiled by the standalone neutron-converter. A model that was never
#     converted produces ~0 delegated nodes and a perfectly reasonable CPU
#     latency.
#
#   * It will not report TOPS derived from latency. TOPS = 2*MACs*IPS is fine
#     arithmetic and a fabrication when the IPS was never proven to be an NPU
#     rate. The Neutron's peak is ~2-3 TOPS [SOURCED] and stays labelled.
#
#   * It will not report ANY timing unless the placement assertion passed.
#     Timing is not evidence. All three Neutron failure modes return a plausible
#     latency (ground-truth §2).
#
# Exit codes: 0 ok · 1 preflight/usage/no-runner · 3 CMA trap
#             4 converter trap or fragmentation · 5 no placement evidence
#             6 thermal refusal · 7 a FOREIGN delegate ran the graph · 8 runner crashed
#             9 the two execution proofs DISAGREE (placement ok, CmaFree flat)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/sysfs.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/board_detect.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/neutron.sh"

MODEL=""
RUNS=50
WARMUP=5
THERMAL_MARGIN_MIN=${IMX95_THERMAL_MARGIN_MIN:-15}   # °C below a zone's own trip
OUTDIR="${IMX95_BENCH_OUTDIR:-/run/media/root-mmcblk0p2/imx95-bench}"

usage() {
    cat <<'EOF'
Usage: bench_npu.sh --model <neutron-converted-int8.tflite> [options]

Required:
  --model PATH     An int8 TFLite model ALREADY COMPILED by the standalone
                   eIQ Neutron SDK CLI:
                     neutron-converter --input m_int8.tflite --target imx95 \
                                       --output m_neutron.tflite
                   ⚠️ The pip neutron_converter_SDK_* packages are BROKEN for this
                   board (microcode 0.0.0 -> delegation collapses to ~1 of N nodes).
                   See references/imx95-ground-truth.md §2.1.

Options:
  --runs N         Timed runs (default 50)
  --warmup N       Warmup runs (default 5)
  --min-margin C   Refuse if any thermal zone is within this many degrees of ITS
                   OWN trip point (default 15). Not an absolute temperature —
                   this board has PMIC zones that report a flat 105 C placeholder.
  --outdir DIR     Where to write the run log (default /run/media/root-mmcblk0p2/...,
                   which is the SMALLER filesystem: 555 M of 11 G, vs / at 8.7 G
                   of 56 G). `df -h` first — free space moves by GB/day (§5).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --model)       MODEL="${2:?}"; shift 2 ;;
        --runs)        RUNS="${2:?}"; shift 2 ;;
        --warmup)      WARMUP="${2:?}"; shift 2 ;;
        --min-margin)  THERMAL_MARGIN_MIN="${2:?}"; shift 2 ;;
        --outdir)      OUTDIR="${2:?}"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

if [ -z "$MODEL" ]; then
    log_error "No --model given."
    log_error "This skill does NOT ship a default model, deliberately: the only models"
    log_error "that run on the Neutron are int8 AND neutron-converter-compiled, and"
    log_error "silently substituting one that is neither is how you benchmark the CPU."
    usage
    exit 1
fi
[ -r "$MODEL" ] || die "Model not readable: ${MODEL}"

# ── Pre-flight. Refuses on its own; we just honour the exit code. ────────────
log_section "Pre-flight"
if ! bash "${SCRIPT_DIR}/check_eiq.sh"; then
    log_error "Pre-flight failed — not running. No number from this board today is an"
    log_error "NPU number until the above is fixed."
    exit 1
fi

# Shared discovery — see lib/neutron.sh. `|| true` so a miss does not kill the
# script mutely under `set -e`; we want the explanation, not a bare exit 1.
BENCHMARK_MODEL="$(neutron_find_runner || true)"
if [ -z "$BENCHMARK_MODEL" ]; then
    neutron_explain_no_runner
    exit 1
fi

# ── Thermal gate — a throttled run is a quiet lie about the silicon ──────────
# Gate on MARGIN TO EACH ZONE'S OWN TRIP POINT, not on an absolute constant.
# On this board three PMIC zones report a flat 105 °C placeholder against a 140 °C
# trip while the SoC sits at 52 °C — an absolute max-vs-80 °C test refuses every
# run on a cold board. See the long note in lib/sysfs.sh.
CUR_TEMP="$(soc_thermal_temp_c 2>/dev/null || echo "")"
MARGIN=""; THERMAL_TIGHTEST_ZONE=""
read -r MARGIN THERMAL_TIGHTEST_ZONE <<<"$(thermal_min_margin_c 2>/dev/null || echo "")"

if [ -n "$CUR_TEMP" ]; then
    log_info "SoC temperature: ${CUR_TEMP} C"
else
    log_warn "Could not read a SoC thermal zone — starting temperature is UNKNOWN."
fi

if [ -n "$MARGIN" ]; then
    log_info "Tightest thermal margin: ${MARGIN} C below trip (zone: ${THERMAL_TIGHTEST_ZONE:-unknown})"
    if [ "$MARGIN" -le "$THERMAL_MARGIN_MIN" ] 2>/dev/null; then
        log_error "Zone '${THERMAL_TIGHTEST_ZONE}' is only ${MARGIN} C below its own trip point"
        log_error "(threshold ${THERMAL_MARGIN_MIN} C). REFUSING."
        log_error "A thermally-throttled run produces a real number for a board state"
        log_error "nobody will remember when the number is quoted. Let it cool."
        exit 6
    fi
else
    log_warn "No thermal zone with a readable trip point — cannot screen for throttling."
fi

# ── THE CENSUS. A measurement without its environment is not provenance. ─────
log_section "Census — the environment IS part of the measurement"
LOAD="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
log_info "loadavg: ${LOAD}"
# Instantaneous snapshot, binary resolved via /proc/PID/exe (never `comm` — it
# truncates at 15 bytes and will hand you a different program's name).
# NOT a CPU-time delta: this answers "who else is resident", not "who is burning
# CPU". Say what it is; an overclaimed methodology is its own defect.
# `awk NR<=20` rather than `head -20`: head exits early, the producing loop takes
# SIGPIPE, and under inherited `pipefail` the command substitution returns 141 and
# `set -e` kills the script before the benchmark runs — silently, with an exit code
# in no table. awk drains its input instead.
log_info "Other resident tenants (snapshot; binary via /proc/PID/exe):"
CENSUS="$(
    for p in /proc/[0-9]*; do
        pid="${p#/proc/}"
        [ "$pid" = "$$" ] && continue
        exe="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
        [ -n "$exe" ] || continue
        case "$exe" in *benchmark_model*|*nnapp*|*kinara*|*python*) echo "  pid ${pid}  ${exe}" ;; esac
    done 2>/dev/null | awk 'NR<=20'
)"
if [ -n "$CENSUS" ]; then
    echo "$CENSUS"
    log_warn "Inference-shaped tenants are resident. This run is measured UNDER that load."
    log_warn "Record it — do not pretend the board was clean."
else
    log_info "  none of interest"
fi

# Do NOT name a cause we have not established. The previous version blamed a 100%-full rootfs
# unconditionally, so a permissions error or a missing parent produced a confident wrong diagnosis
# — and the free-space claim it rested on is itself in conflict (ground-truth §5). Print the real
# error and the real `df`, then let the reader decide.
if ! MKDIR_ERR="$(mkdir -p "$OUTDIR" 2>&1)"; then
    log_error "Cannot create ${OUTDIR}"
    log_error "  mkdir: ${MKDIR_ERR:-(no message)}"
    log_error "  df for the nearest existing parent:"
    _P="$OUTDIR"; while [ ! -d "$_P" ] && [ "$_P" != "/" ]; do _P="$(dirname "$_P")"; done
    df -h "$_P" 2>&1 | awk 'NR<=2 {print "    " $0}'
    die "Refusing to run: no writable output directory."
fi
RUNLOG="${OUTDIR}/neutron-run-$(timestamp).log"

# ── Run ──────────────────────────────────────────────────────────────────────
log_section "Run"
neutron_cma_snapshot_before
neutron_cma_watch_start        # sample DURING the run — see lib/neutron.sh for why not around it
# Reap the sampler AND its temp file on every exit path. The file is only removed
# on neutron_cma_execution_evidence's success path, so exits 3/4/5/7/8 (placement
# fails before Gate 2) would otherwise leak it into tmpfs — i.e. into RAM — and
# CMA-trap debugging is precisely the scenario with many consecutive failed runs.
trap 'neutron_cma_watch_stop; rm -f "${_NEUTRON_CMA_WATCH_FILE:-}" 2>/dev/null || true' EXIT INT TERM

log_info "Model    : ${MODEL}"
log_info "Delegate : ${NEUTRON_DELEGATE_PATH}"
log_info "Runs     : ${RUNS} (${WARMUP} warmup)"
log_info "Log      : ${RUNLOG}"

set +e
# --use_xnnpack=false is NOT optional. benchmark_model applies XNNPACK (CPU) by
# default, and XNNPACK's placement message has the SAME SHAPE as Neutron's
# ("N nodes delegated out of M nodes with K partitions"). Left enabled, it both
# produces a spoofable placement line and competes for the graph, masking the
# converter trap by claiming the nodes Neutron did not take.
"$BENCHMARK_MODEL" \
    --graph="${MODEL}" \
    --external_delegate_path="${NEUTRON_DELEGATE_PATH}" \
    --use_xnnpack=false \
    --num_runs="${RUNS}" \
    --warmup_runs="${WARMUP}" \
    --min_secs=0 \
    >"${RUNLOG}" 2>&1
RUN_RC=$?
set -e
log_debug "benchmark_model exit: ${RUN_RC}"

# A crashed run must not exit 0. The delegate can apply (placement line printed)
# and the binary then die — placement would pass, timing would be UNKNOWN, and the
# script would report "healthy". Capturing the exit code and only log_debug-ing it,
# as the first version did, is the same warn-and-continue shape this repo forbids.
if [ "$RUN_RC" -ne 0 ]; then
    log_error "The runner exited ${RUN_RC}. This run did not complete."
    log_error "Log: ${RUNLOG}"
    tail -15 "${RUNLOG}" >&2 || true
    neutron_cma_watch_stop
    exit 8
fi

neutron_cma_watch_stop
neutron_cma_check_after

# ── GATE 1 — placement ───────────────────────────────────────────────────────
log_section "Gate 1/2 — placement census"
set +e
neutron_assert_placement "${RUNLOG}"
PLACEMENT_RC=$?
set -e

if [ "$PLACEMENT_RC" -ne 0 ]; then
    log_error ""
    log_error "NO NUMBER WILL BE REPORTED FROM THIS RUN."
    log_error "Full log kept for inspection: ${RUNLOG}"
    exit "$PLACEMENT_RC"
fi

# ── GATE 2 — CmaFree movement ────────────────────────────────────────────────
# Independent of every log string, which is the point: the CMA-trap error message
# disappears once the neutron DTB is booted, so a string-based detector passes on
# a healthy board. A pool that never moves during an inference is a fallback.
log_section "Gate 2/2 — CmaFree movement (independent of any log wording)"
set +e
neutron_cma_execution_evidence
CMA_RC=$?
set -e

case "$CMA_RC" in
    0) log_info "CmaFree dropped ${NEUTRON_CMA_DROP_MB} MB during the run (min ${NEUTRON_CMA_MIN_MB} MB)."
       log_info "Consistent with a real Neutron allocation — second proof of execution."
       log_info "(CmaFree sums linux,cma + neutron_memory and this kernel has no per-pool"
       log_info " accounting: this shows an allocation occurred, NOT that linux,cma is healthy.)" ;;
    1) log_error "CmaFree did NOT move measurably during the run (min ${NEUTRON_CMA_MIN_MB} MB,"
       log_error "baseline ${_NEUTRON_CMA_FREE_BASE} MB). A real offload drops it; a silent CPU"
       log_error "fallback does not."
       log_error ""
       log_error "TWO INDEPENDENT SIGNALS DISAGREE: placement says the NPU ran, CmaFree says"
       log_error "it did not. REFUSING — a disagreement between the only two proofs we have is"
       log_error "not a caveat to print above a number, it is a reason to withhold the number."
       log_error "(Exception to check first: the ORT Neutron EP path draws from the dedicated"
       log_error " 4 GiB neutron_memory pool, not linux,cma, so this signal may legitimately"
       log_error " not apply there. This script drives the TFLite delegate, where it should.)"
       log_error "To measure anyway: IMX95_NEUTRON_CMA_MIN_DROP_MB=0"
       exit 9 ;;
    *) log_warn "CmaFree evidence UNAVAILABLE (no samples or no baseline)." ;;
esac

# ── Report. Only now, and only with tags. ────────────────────────────────────
log_section "Result"

AVG_US="$(sed -nE 's/.*Inference \(avg\): *([0-9.]+).*/\1/p' "${RUNLOG}" | tail -1)"

echo
echo "  eIQ Neutron — i.MX95"
echo "  ------------------------------------------------------------------"
prov MEASURED "model"              "$(basename "${MODEL}")"
prov MEASURED "delegate"           "$(basename "${NEUTRON_DELEGATE_PATH}")"
prov MEASURED "nodes delegated"    "${NEUTRON_NODES_DELEGATED}/${NEUTRON_NODES_TOTAL}"
if [ -n "${NEUTRON_PARTITIONS}" ]; then prov MEASURED "partitions" "${NEUTRON_PARTITIONS}"
else prov UNKNOWN "partitions" "" "runner printed no 'with K partitions' clause"; fi
if [ -n "$AVG_US" ]; then
    prov MEASURED "inference (avg)" "$(awk -v u="$AVG_US" 'BEGIN{printf "%.2f ms", u/1000}')" \
         "under the census above"
else
    prov UNKNOWN  "inference (avg)" "" "runner printed no parseable timing"
fi
case "$CMA_RC" in
    0) prov MEASURED "CmaFree drop"  "${NEUTRON_CMA_DROP_MB} MB" "2nd proof of execution" ;;
    1) prov MEASURED "CmaFree drop"  "0 MB" "⚠️ CONFLICTS with placement — investigate" ;;
    *) prov UNKNOWN  "CmaFree drop"  "" "sampler unavailable" ;;
esac
# A failed read is UNKNOWN, never MEASURED. Writing "${CUR_TEMP:-unknown} C" under
# a MEASURED tag launders prov()'s refusal: the default exists only to give the
# empty-value check something non-empty to accept, which defeats the check.
if [ -n "$CUR_TEMP" ]; then prov MEASURED "SoC temperature"  "${CUR_TEMP} C"
else                       prov UNKNOWN  "SoC temperature"  "" "no SoC thermal zone readable"; fi
if [ -n "$MARGIN" ];   then prov MEASURED "thermal margin"   "${MARGIN} C" "to '${THERMAL_TIGHTEST_ZONE}' trip"
else                       prov UNKNOWN  "thermal margin"   "" "no readable trip point"; fi
if [ "$LOAD" != "?" ];  then prov MEASURED "loadavg at start" "${LOAD}"
else                         prov UNKNOWN  "loadavg at start" "" "/proc/loadavg unreadable"; fi
prov SOURCED  "Neutron peak"       "~2-3 INT8 TOPS" "vendor class figure — NOT derived from the above"
echo "  ------------------------------------------------------------------"
echo
log_info "This is a batch-1 single-stream figure. It is NOT the whole-accelerator"
log_info "throughput — that is 86.25 IPS 4-worker [MEASURED, fleet] and a different metric."
log_info "For reference points with provenance, see references/imx95-ground-truth.md §2.5."
log_info "Run log: ${RUNLOG}"
exit 0
