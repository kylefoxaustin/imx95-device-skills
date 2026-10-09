#!/usr/bin/env bash
# skills/imx95-ara240/scripts/run_dvm.sh
#
# Run a .dvm model on the Kinara ARA240 via nnapp.
#
# Uses the random-input trick (ground-truth §3): leave input_path EMPTY in the
# generated config and nnapp feeds random inputs — no preprocessed .dat needed.
#
# ⚠️ RANDOM INPUTS MEASURE THROUGHPUT, NOT CORRECTNESS. A model fed noise will
# happily report a great IPS while computing nothing meaningful. Any number this
# script emits is tagged as what it is.
#
# Exit codes: 0 ok · 1 usage/preflight · 2 nnapp failed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/neutron.sh"   # for prov()

NNAPP="/usr/share/rt-sdk-ara240_2.1.1/nnapp/nnapp"
MODEL=""
EP="all"
OUTDIR="${IMX95_ARA_OUTDIR:-/run/media/root-mmcblk0p2/imx95-ara240}"

usage() {
    cat <<'EOF'
Usage: run_dvm.sh --model <model.dvm> [--ep all] [--outdir DIR]

  --model   A .dvm compiled HOST-SIDE with the Kinara SDK. There is no on-board
            compiler; a .tflite/.onnx will not work here.
  --ep      Execution provider list for nnapp (default: all)
  --outdir  Where to write config + log. Defaults to the eMMC data partition.
            Neither partition has guaranteed headroom — `df -h` both first
            (ground-truth §5: the free-space figures are in conflict).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --model)  MODEL="${2:?}"; shift 2 ;;
        --ep)     EP="${2:?}"; shift 2 ;;
        --outdir) OUTDIR="${2:?}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

[ -n "$MODEL" ] || { log_error "No --model given."; usage; exit 1; }
[ -r "$MODEL" ] || die "Model not readable: ${MODEL}"
case "$MODEL" in
    *.dvm) ;;
    *) log_error "Model is not a .dvm: ${MODEL}"
       log_error "The ARA240 runs Kinara .dvm only, compiled host-side. Refusing rather"
       log_error "than letting nnapp fail in a way that reads like a hardware problem."
       exit 1 ;;
esac

log_section "ARA240 pre-flight"
if ! bash "${SCRIPT_DIR}/check_ara240.sh"; then
    log_error "ARA240 pre-flight failed — not running."
    exit 1
fi

log_warn "Reminder: the pre-flight above did NOT establish that the device is free."
log_warn "If another session is mid-inference, your numbers and theirs are both affected."

mkdir -p "$OUTDIR" 2>/dev/null || die "Cannot create ${OUTDIR} (rootfs full? use the eMMC data partition)"
STAMP="$(timestamp)"
CFG="${OUTDIR}/nnapp-${STAMP}.yaml"
RUNLOG="${OUTDIR}/ara240-run-${STAMP}.log"

# input_path deliberately EMPTY -> nnapp generates random inputs. [MEASURED]
# ⚠️ Only `path:` and the empty `input_path:` are measured facts about this schema.
# `ep_list:` and the overall YAML shape are [UNVERIFIED] — taken from usage notes,
# not from a spec anyone in the fleet has confirmed. It fails safe (nnapp errors
# and we exit 2 rather than silently mis-running), but it is not established.
cat > "$CFG" <<EOF
model:
  path: ${MODEL}
  input_path:
ep_list: ["${EP}"]
EOF

log_section "Run"
log_info "Model : ${MODEL}"
log_info "Config: ${CFG}  (input_path empty => RANDOM INPUTS)"
log_info "Log   : ${RUNLOG}"

LOAD="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
log_info "loadavg at start: ${LOAD}"

set +e
"$NNAPP" -c "$CFG" >"$RUNLOG" 2>&1
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
    log_error "nnapp exited ${RC}. Log: ${RUNLOG}"
    tail -20 "$RUNLOG" >&2 || true
    exit 2
fi

log_section "Result"
# ⚠️ The capture group MUST be preceded by a non-number class.
# The first version used 's/.*([0-9.]+) *(IPS|...)/\1/p'. The greedy leading `.*`
# eats as much as it can, so "Average throughput: 298.4 IPS" captured just "4" —
# and the script then printed "4 IPS [MEASURED]" for a 298 IPS run. A two-orders-
# of-magnitude fabrication wearing a provenance tag, in the repo whose entire
# premise is that the tags mean something.
HW_MS="$(sed -nE 's/.*[Hh]ardware[^0-9]*([0-9]+(\.[0-9]+)?) *ms.*/\1/p' "$RUNLOG" | tail -1)"
IPS="$(sed -nE 's/.*(^|[^0-9.])([0-9]+(\.[0-9]+)?) *(IPS|inferences\/sec).*/\2/p' "$RUNLOG" | tail -1)"

echo
echo "  Kinara ARA240 — i.MX95 M.2"
echo "  ------------------------------------------------------------------"
prov MEASURED "model"        "$(basename "$MODEL")"
prov MEASURED "inputs"       "RANDOM" "throughput only — NOT a correctness result"
[ -n "$HW_MS" ] && prov MEASURED "hardware time" "${HW_MS} ms" "under the load below" \
                || prov UNKNOWN  "hardware time" "" "nnapp printed no parseable timing"
[ -n "$IPS" ]   && prov MEASURED "throughput"    "${IPS} IPS" \
                || prov UNKNOWN  "throughput"    "" "not parseable from nnapp output"
prov MEASURED "loadavg at start" "${LOAD}"
prov UNKNOWN  "device exclusivity" "" "ARA240 occupancy is host-undetectable"
echo "  ------------------------------------------------------------------"
echo
log_info "Fleet reference (ground-truth §3): yolov8n hardware 296-298 IPS [MEASURED],"
log_info "but deployed e2e only 23.4 fps [MEASURED] — the frame is ~71% A55 host, not PCIe."
log_info "Do not quote the hardware IPS as a deployment number."
log_info "Log: ${RUNLOG}"
exit 0
