#!/usr/bin/env bash
# skills/imx95-npu-benchmark/evals/eval.sh
#
# Eval for the placement gate — the safety property that must never regress.
#
# Runs on ANY machine: it feeds synthetic runtime logs to neutron_assert_placement()
# and asserts the exit code. No board, no NPU, no model. That is deliberate — a
# safety property you can only test on hardware you have to reserve is a safety
# property nobody tests.
#
# TWO BUGS THIS FILE EXISTS BECAUSE OF, both found by review rather than by use:
#
#  1. The healthy signature and the converter-trap signature BOTH read "1 node
#     delegated". The first gate classified the healthy case as a trap.
#
#  2. The gate matched the SHAPE of a placement line without requiring the word
#     "neutron" — and benchmark_model applies XNNPACK (CPU) by default, whose
#     message has the identical shape. A pure-CPU run exited 0 as [MEASURED],
#     and in the realistic ordering (Neutron takes 1 of 310, XNNPACK takes the
#     rest) `tail -1` picked XNNPACK's line and masked the trap outright.
#     The spoof cases below are what keep that fixed.

set -uo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${EVAL_DIR}/../../.." && pwd)"
export NO_COLOR=1
# An operator override would make the delegate-constant assertion below vacuous.
unset IMX95_NEUTRON_DELEGATE IMX95_NEUTRON_FUSED_TOTAL_MAX IMX95_NEUTRON_ALLOW_FRAGMENTED
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/sysfs.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/neutron.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

mk() { printf '%s\n' "$2" > "${TMP}/$1.log"; }

check() {
    local name="$1" want="$2" got
    neutron_assert_placement "${TMP}/${name}.log" >/dev/null 2>&1; got=$?
    if [ "$got" -eq "$want" ]; then
        echo "[PASS] ${name}: exit ${got}"; PASS=$((PASS+1))
    else
        echo "[FAIL] ${name}: expected exit ${want}, got ${got}"; FAIL=$((FAIL+1))
    fi
}

ok() { echo "[PASS] $1"; PASS=$((PASS+1)); }
no() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== imx95-npu-benchmark :: placement gate ==="

# ── Healthy ──────────────────────────────────────────────────────────────────
# A fused graph with a small A55 tail. Only ONE node delegated — and that is
# correct: the whole conv backbone is fused into one NeutronGraph op.
mk healthy 'INFO: Loaded external delegate
NeutronDelegate: 1 nodes delegated out of 33 nodes with 1 partitions
INFO: Inference (avg): 32080.5'
check healthy 0

mk fused_tail 'NeutronDelegate: 1 nodes delegated out of 34 nodes with 1 partitions
INFO: Inference (avg): 101500'
check fused_tail 0

# ── Converter trap: same delegated count, unfused total ──────────────────────
mk converter 'NeutronDelegate: 1 nodes delegated out of 310 nodes with 1 partitions
INFO: Inference (avg): 2079000'
check converter 4

# An unfused total is the trap signature BY ITSELF. A gate that also required
# "delegated <= 2" let this 98%-CPU run through as healthy.
mk partial_5_of_310 'NeutronDelegate: 5 nodes delegated out of 310 nodes with 5 partitions
INFO: Inference (avg): 1900000'
check partial_5_of_310 4

# ── Fragmentation: many partitions on an otherwise small graph ───────────────
# Only DEPTH_TO_SPACE may legitimately fall to the A55; more boundary crossings
# is a topology regression, and it is what bounds the deployed e2e number.
mk fragmented 'NeutronDelegate: 8 nodes delegated out of 40 nodes with 4 partitions
INFO: Inference (avg): 60000'
check fragmented 4

# ── CMA trap ─────────────────────────────────────────────────────────────────
mk cma 'Neutron hardware init failed!!! All nodes will be assigned to CPU
NeutronDelegate: 0 nodes delegated out of 33 nodes with 0 partitions
INFO: Inference (avg): 385000'
check cma 3

mk cma_noline 'Neutron hardware init failed!!! All nodes will be assigned to CPU
INFO: Inference (avg): 385000'
check cma_noline 3

# 0 delegated with NO signature: cause is ambiguous (unconverted model is the
# likely one), so it routes to the convert-time diagnosis.
mk zero_no_signature 'NeutronDelegate: 0 nodes delegated out of 23 nodes with 0 partitions
INFO: Inference (avg): 120000'
check zero_no_signature 4

# ── No evidence at all ───────────────────────────────────────────────────────
# There IS a latency in this log. It must not be treated as success.
mk silent 'INFO: Inference (avg): 384999.1'
check silent 5

# ── 🔴 THE SPOOF CASES — a CPU delegate must never pass as the NPU ───────────
mk xnnpack_only 'INFO: Created TensorFlow Lite XNNPACK delegate for CPU.
XNNPack delegate: 30 nodes delegated out of 33 nodes with 1 partitions.
INFO: Inference (avg): 210000'
check xnnpack_only 7

# The realistic masking order: Neutron takes 1 of 310, XNNPACK takes the rest,
# and a `tail -1` on a shape-only match sees only XNNPACK.
mk neutron_then_xnnpack 'NeutronDelegate: 1 nodes delegated out of 310 nodes with 1 partitions
XNNPack delegate: 280 nodes delegated out of 310 nodes with 1 partitions.
INFO: Inference (avg): 2079000'
check neutron_then_xnnpack 4

# 🔴 PREFIX SPOOF — a foreign delegate's line on a log whose lines carry a
# neutron-containing prefix (logger tag, wrapper echoing the model filename).
# Anchoring on the bare word "neutron" let this parse AS Neutron placement and
# simultaneously excluded it from the foreign check => exit 0 on a pure-CPU run.
mk prefix_spoof 'model_neutron: XNNPack delegate: 30 nodes delegated out of 33 nodes with 1 partitions.
INFO: Inference (avg): 210000'
check prefix_spoof 7

# The REAL string emitted by benchmark_model on this board [MEASURED 2026-08-12].
# Note "NeutronDelegate delegate:" — the word delegate TWICE. The native C harness
# prints "NeutronDelegate:" (once). Both must parse; neither prefix is canonical.
mk real_benchmark_model 'INFO: NeutronDelegate delegate: 1 nodes delegated out of 33 nodes with 1 partitions.
INFO: Inference (avg): 43620.1'
check real_benchmark_model 0

mk real_c_harness 'NeutronDelegate: 1 nodes delegated out of 3 nodes with 1 partitions'
check real_c_harness 0

# XNNPACK masking the CMA trap.
mk xnnpack_masks_cma 'Neutron hardware init failed!!! All nodes will be assigned to CPU
NeutronDelegate: 0 nodes delegated out of 33 nodes with 0 partitions
XNNPack delegate: 30 nodes delegated out of 33 nodes with 1 partitions.'
check xnnpack_masks_cma 3

# ── Parser ───────────────────────────────────────────────────────────────────
neutron_parse_placement "${TMP}/healthy.log" >/dev/null 2>&1
if [ "${NEUTRON_NODES_DELEGATED}" = "1" ] && [ "${NEUTRON_NODES_TOTAL}" = "33" ] \
   && [ "${NEUTRON_PARTITIONS}" = "1" ]; then
    ok "parser: extracted 1/33 nodes, 1 partition"
else
    no "parser: got ${NEUTRON_NODES_DELEGATED}/${NEUTRON_NODES_TOTAL}, ${NEUTRON_PARTITIONS} part"
fi

# The parser must attribute the NEUTRON line, not the last line of any delegate.
neutron_parse_placement "${TMP}/neutron_then_xnnpack.log" >/dev/null 2>&1
if [ "${NEUTRON_NODES_TOTAL}" = "310" ] && [ "${NEUTRON_NODES_DELEGATED}" = "1" ]; then
    ok "parser: attributes the Neutron line, not XNNPACK's trailing one"
else
    no "parser: picked ${NEUTRON_NODES_DELEGATED}/${NEUTRON_NODES_TOTAL} — XNNPACK's line won"
fi

if [ -n "${NEUTRON_FOREIGN_PLACEMENT}" ]; then
    ok "parser: records the foreign delegate's placement line"
else
    no "parser: NEUTRON_FOREIGN_PLACEMENT not set for a mixed log"
fi

# ── Constants ────────────────────────────────────────────────────────────────
if [ "$NEUTRON_DELEGATE_PATH" = "/usr/lib/libneutron_delegate.so" ]; then
    ok "delegate constant is the i.MX95 Neutron delegate"
else
    no "delegate constant is '${NEUTRON_DELEGATE_PATH}'"
fi

# The regression guard on the ORIGINAL defect. The first version of this test was
# `grep -qE 'ethosu…' file | grep -qv '^#'` — the leading -q prints nothing, so the
# second grep always saw empty input, always exited 1, and the test ALWAYS PASSED.
# It was decorative. This version greps for live (non-comment) references and
# fails if any exist.
if grep -E 'libethosu_delegate|libvx_delegate' "${REPO_ROOT}/lib/sysfs.sh" 2>/dev/null \
     | grep -Ev '^[[:space:]]*#' | grep -q .; then
    no "a LIVE other-SoC delegate path exists in lib/sysfs.sh"
else
    ok "no live other-SoC delegate paths in lib/sysfs.sh"
fi

# Self-test the guard: it must be capable of failing.
printf 'x=/usr/lib/libethosu_delegate.so\n' > "${TMP}/decoy.sh"
if grep -E 'libethosu_delegate|libvx_delegate' "${TMP}/decoy.sh" 2>/dev/null \
     | grep -Ev '^[[:space:]]*#' | grep -q .; then
    ok "guard self-test: it detects a live reference when one exists"
else
    no "guard self-test: the guard cannot detect a live reference — it is decorative"
fi

# ── prov() ───────────────────────────────────────────────────────────────────
prov BOGUS "x" "1" >/dev/null 2>&1 && no "prov() accepted an invalid tag" \
                                   || ok "prov() refuses an invalid provenance tag"
prov MEASURED "x" "" >/dev/null 2>&1 && no "prov() accepted an empty MEASURED value" \
                                     || ok "prov() refuses an empty MEASURED value"
prov UNKNOWN "x" "" >/dev/null 2>&1 && ok "prov() permits an empty UNKNOWN value" \
                                    || no "prov() rejected a legitimate empty UNKNOWN"

echo "--- ${PASS} passed, ${FAIL} failed ---"
[ "$FAIL" -eq 0 ]
