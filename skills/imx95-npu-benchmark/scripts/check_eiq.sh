#!/usr/bin/env bash
# skills/imx95-npu-benchmark/scripts/check_eiq.sh
#
# Neutron pre-flight. REFUSES rather than degrades.
#
# This script replaces a version that searched six delegate paths — all of them
# belonging to other i.MX parts — and, on finding none, printed
# "NPU inference will fall back to CPU" and let the benchmark proceed on the
# A55s. Everything below is built so that cannot happen again.
#
# Exit codes — DELIBERATELY DISJOINT from bench_npu.sh's.
#
# They used to overlap: this script's 3 meant "/dev/neutron0 missing" while
# SKILL.md's table (written for bench_npu.sh) said 3 = CMA trap. Since SKILL.md
# also tells the agent to run this script standalone, an agent that got exit 3
# from a missing driver would confidently deliver the CMA-trap remediation
# speech — a wrong diagnosis produced by two correct documents.
#
#   0   ready — Neutron present and the correct delegate is loadable
#   10  not an i.MX95
#   11  delegate missing (or only another SoC's delegate is present)
#   12  /dev/neutron0 missing — driver did not bind
#   13  no TFLite runner (benchmark_model) available

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

QUIET="${QUIET:-0}"
say() { [ "$QUIET" = "1" ] || log_info "$@"; }

log_section "eIQ Neutron pre-flight"

# ── 1. Is this actually an i.MX95? ───────────────────────────────────────────
# The delegate is SoC-specific. Running this on an i.MX93 or 8MP would find the
# wrong library and "work".
if ! board_is_imx95 2>/dev/null; then
    log_error "This does not look like an i.MX95."
    log_error "Refusing: the Neutron delegate is i.MX95-specific, and the neighbouring"
    log_error "i.MX parts ship delegates with confusingly similar names (ground-truth §1.1)."
    exit 10
fi
say "Board: i.MX95 confirmed."

# ── 2. Did the Neutron driver bind? ──────────────────────────────────────────
if ! neutron_device_present; then
    log_error "${NEUTRON_DEVICE} is missing — the Neutron driver did not bind."
    log_error "Nothing downstream can be an NPU measurement. Check the boot DTB"
    log_error "(this board should boot imx95-19x19-frdm-pro-neutron.dtb — ground-truth §2.3)."
    exit 12
fi
say "Neutron device: ${NEUTRON_DEVICE} present."
say "  (presence only — this does NOT mean the NPU is free; see the ARA240 note in §3.1"
say "   of the ground truth for why occupancy checks must not overclaim.)"

# ── 3. The delegate. One path. Refuse on failure. ────────────────────────────
if ! neutron_require_delegate; then
    exit 11
fi
say "Delegate: ${NEUTRON_DELEGATE_PATH}"

# Report other-SoC delegates even on success — their presence is what misled the
# original implementation, and a reader should know they are on the box.
neutron_report_wrong_soc_delegates || true

# ── 4. A runner to actually execute a graph ──────────────────────────────────
BENCHMARK_MODEL="$(neutron_find_runner || true)"
if [ -z "$BENCHMARK_MODEL" ]; then
    neutron_explain_no_runner
    exit 13
fi
say "Runner: ${BENCHMARK_MODEL}"

# ── 5. CMA state — a precondition, not a curiosity ───────────────────────────
CMA_TOTAL="$(cma_total_mb 2>/dev/null || echo "")"
CMA_FREE="$(cma_free_mb 2>/dev/null || echo "")"
if [ -n "$CMA_FREE" ]; then
    say "CMA: ${CMA_FREE} MB free of ${CMA_TOTAL} MB total."
    if [ "${CMA_TOTAL:-0}" -gt 4000 ] 2>/dev/null; then
        say "  CmaTotal > 4 GiB => the neutron DTB is booted (ground-truth §2.3). Leave it."
        say "  ⚠️ CmaFree here SUMS linux,cma (960 MiB) + neutron_memory (4096 MiB); there is no"
        say "     per-pool accounting on this kernel, so a healthy-looking figure does NOT prove"
        say "     the 960 MiB pool the TFLite delegate uses is free."
    fi
else
    log_warn "Could not read CmaFree from /proc/meminfo."
    log_warn "The CMA trap (ground-truth §2.2) cannot be screened for on this run."
fi

log_info "Pre-flight PASSED — the Neutron is present and the correct delegate is loadable."
log_info "NOTE: this proves the NPU CAN run. Only the placement line proves it DID."
exit 0
