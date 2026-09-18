#!/bin/bash
# lib/neutron.sh — eIQ Neutron helpers for imx95-device-skills
#
#   source "${SCRIPT_DIR}/../../lib/common.sh"
#   source "${SCRIPT_DIR}/../../lib/neutron.sh"
#
# ─────────────────────────────────────────────────────────────────────────────
# DESIGN NOTE — read this before changing anything here.
#
# The version of this repo written without board access searched SIX delegate
# paths, all of them belonging to OTHER SoCs (libethosu_delegate.so = i.MX93's
# Ethos-U65; libvx_delegate.so = i.MX8M Plus's VeriSilicon VX). On this board it
# found none, logged "NPU inference will fall back to CPU", and then benchmarked
# six Cortex-A55 cores and reported the result as NPU performance.
#
# The warning was present. The warning was correct. The warning was useless,
# because a warning printed above a number is read as a caveat and an exit code
# is read as a stop.
#
# So the contract in this file is:
#
#   1. There is ONE delegate path. We do not "search common locations" — a
#      search that succeeds on the wrong library is worse than a failure.
#   2. Nothing here EVER falls back to CPU silently. Not being able to use the
#      NPU is a REFUSAL (non-zero exit), never a degraded success.
#   3. Placement is the only proof of execution. Latency is not evidence: all
#      three Neutron failure modes return a plausible latency with no NPU in it.
#      If we cannot find the placement line, we DO NOT KNOW that the NPU ran,
#      and "we do not know" is reported as failure, not as success.
#   4. Every number that leaves this file carries a provenance tag or it does
#      not leave this file.
#
# Facts here come from references/imx95-ground-truth.md. Change them there first.
# ─────────────────────────────────────────────────────────────────────────────

[[ -n "${_IMX95_NEUTRON_SH_LOADED:-}" ]] && return 0
_IMX95_NEUTRON_SH_LOADED=1

# ── The constants. One value each. See ground-truth §2. ──────────────────────

# The i.MX95 TFLite Neutron delegate that is CONFIRMED to delegate. [MEASURED]
# Override for a genuinely relocated BSP with IMX95_NEUTRON_DELEGATE=/path.
#
# ⚠️ ASSERT EXISTS, NEVER ASSERT EXCLUSIVE.
# Our own first fix hardcoded this single path and called it "the" delegate.
# @imx95-isp: "a skill that greps for exactly one path is as brittle as the
# i.MX93 bug you found." Correct — we over-rotated from "search six wrong paths"
# to "assert one right path", when the real property is exists-and-loadable.
# There are TWO Neutron delegate files on the board (see below).
NEUTRON_DELEGATE_PATH="${IMX95_NEUTRON_DELEGATE:-/usr/lib/libneutron_delegate.so}"

# Other Neutron-family delegates known to exist on this board. Present, untested.
# We REPORT these; we never silently bind to one. [MEASURED @imx95-isp/@ollama_95_neutron]
NEUTRON_OTHER_DELEGATES=(
    "/usr/lib/liblitert_neutron_delegate.so:LiteRT-flavoured Neutron delegate — present, UNTESTED; go-forward status [UNKNOWN]"
)

# The ONNX Runtime Neutron EP is a SEPARATE STACK with a SEPARATE placement signal.
# It never loads the TFLite delegate. Do not cross-apply the two contracts.
NEUTRON_ORT_LIBS=(
    "/usr/lib/libonnxruntime.so.1.24.3"
    "/usr/lib/libNeutronDriver.so"
)

# The Neutron character device. [MEASURED]
NEUTRON_DEVICE="${IMX95_NEUTRON_DEVICE:-/dev/neutron0}"

# Delegates that belong to OTHER i.MX parts. If one of these is on the box we say
# so loudly, because its presence is exactly what seduced the first version.
NEUTRON_WRONG_SOC_DELEGATES=(
    "/usr/lib/libethosu_delegate.so:Arm Ethos-U65 — this is the i.MX93 NPU delegate"
    "/usr/lib/libvx_delegate.so:VeriSilicon/Vivante VX — this is the i.MX8M Plus NPU delegate"
)

# ─────────────────────────────────────────────────────────────────────────────
# PROVENANCE
# ─────────────────────────────────────────────────────────────────────────────

# prov TAG LABEL VALUE [NOTE]
#   Emit a number with its provenance tag. Refuses to emit an untagged number.
#   Valid tags: MEASURED SOURCED DERIVED UNVERIFIED UNKNOWN
prov() {
    local tag="${1:-}" label="${2:-}" value="${3:-}" note="${4:-}"
    case "$tag" in
        MEASURED|SOURCED|DERIVED|UNVERIFIED|UNKNOWN) ;;
        *)  log_error "prov(): refusing to emit '${label}' — invalid or missing provenance tag '${tag}'."
            log_error "        A number without a tag is not a number. See references/imx95-ground-truth.md §0."
            return 2 ;;
    esac
    if [ -z "$value" ] && [ "$tag" != "UNKNOWN" ]; then
        log_error "prov(): refusing to emit '${label}' — empty value tagged ${tag}."
        return 2
    fi
    printf '  %-34s %-14s [%s]%s\n' "$label" "$value" "$tag" "${note:+  $note}"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRESENCE — is the Neutron here at all?
# ─────────────────────────────────────────────────────────────────────────────

# neutron_device_present — 0 if /dev/neutron0 exists.
#   NOTE: presence, NOT availability. This says the driver bound; it says nothing
#   about whether another tenant holds the NPU.
neutron_device_present() {
    [ -e "$NEUTRON_DEVICE" ]
}

# neutron_delegate_found — 0 if the ONE correct delegate is present.
neutron_delegate_found() {
    [ -r "$NEUTRON_DELEGATE_PATH" ]
}

# neutron_report_wrong_soc_delegates — print any other-SoC delegates found.
#   Informational, but load-bearing: if one of these is present and the Neutron
#   one is not, a "search common paths" implementation would bind to it happily.
neutron_report_wrong_soc_delegates() {
    local entry path why found=1
    for entry in "${NEUTRON_WRONG_SOC_DELEGATES[@]}"; do
        path="${entry%%:*}"; why="${entry#*:}"
        if [ -e "$path" ]; then
            log_warn "Found ${path} — ${why}."
            log_warn "  This is NOT the i.MX95 delegate and must never be loaded here."
            found=0
        fi
    done
    return $found
}

# neutron_report_other_delegates — enumerate OTHER Neutron delegates on the box.
#   Informational and deliberately loud: the delegate list is NOT closed, and a
#   reader who believes it is will write the next brittle check.
neutron_report_other_delegates() {
    local entry path why
    for entry in "${NEUTRON_OTHER_DELEGATES[@]}"; do
        path="${entry%%:*}"; why="${entry#*:}"
        [ -e "$path" ] && log_info "Also present: ${path} — ${why}"
    done
    return 0
}

# neutron_ort_stack_present — is the ONNX Runtime Neutron EP stack installed?
#   A DIFFERENT stack with a DIFFERENT placement contract. Reported so a caller
#   never assumes "Neutron" means "the TFLite delegate".
neutron_ort_stack_present() {
    local lib
    for lib in "${NEUTRON_ORT_LIBS[@]}"; do
        [ -e "$lib" ] || return 1
    done
    return 0
}

# neutron_require_delegate — REFUSE unless the correct delegate is usable.
#   This is the gate. It does not warn-and-continue. Exit 1 on failure.
neutron_require_delegate() {
    if neutron_delegate_found; then
        log_debug "Neutron delegate: ${NEUTRON_DELEGATE_PATH}"
        neutron_report_other_delegates
        return 0
    fi

    log_error "eIQ Neutron delegate NOT found at: ${NEUTRON_DELEGATE_PATH}"
    log_error ""
    log_error "REFUSING TO RUN. This is deliberate — see lib/neutron.sh design note."
    log_error "Without the delegate, inference runs on the 6x Cortex-A55 and returns a"
    log_error "perfectly plausible latency that is NOT an NPU measurement."
    log_error ""
    neutron_report_wrong_soc_delegates && {
        log_error ""
        log_error "An other-SoC delegate IS present (above). Do not point this skill at it."
    }
    log_error "If your BSP genuinely relocated the library, set:"
    log_error "    IMX95_NEUTRON_DELEGATE=/real/path/libneutron_delegate.so"
    return 1
}

# neutron_find_runner — locate a TFLite runner. Prints the path, or returns 1.
#
#   Single source of truth, on purpose. check_eiq.sh used to `export` its result
#   "for the benchmark script" — which does nothing, because bench_npu.sh runs it
#   as a CHILD process. So bench_npu.sh re-implemented the same candidate list,
#   and the two had to be kept in sync by hand. Worse, bench_npu's copy assigned
#   from a command substitution under `set -e`, so when nothing was found the
#   script died mute at that line, printing none of the sealed-Yocto guidance
#   check_eiq.sh had been written to give.
neutron_find_runner() {
    local cand
    for cand in \
        /usr/bin/tensorflow-lite-2.19.0/examples/benchmark_model \
        /usr/bin/benchmark_model \
        "$(command -v benchmark_model 2>/dev/null || true)"; do
        if [ -n "$cand" ] && [ -x "$cand" ]; then printf '%s\n' "$cand"; return 0; fi
    done
    return 1
}

# neutron_explain_no_runner — the guidance, in one place, for both callers.
neutron_explain_no_runner() {
    log_error "No TFLite runner (benchmark_model) found."
    log_error "The board is a sealed Yocto image with no working package feed"
    log_error "(ground-truth §5) — do NOT expect opkg/apt to install it. Either use the"
    log_error "BSP's tensorflow-lite examples directory, or build a native harness:"
    log_error "  /usr/lib/libtensorflow-lite.so.2.19.0 exports the full TFLite C API,"
    log_error "  and gcc 15.2 is on-board. No headers ship — fetch v2.19.0 C headers."
}

# ─────────────────────────────────────────────────────────────────────────────
# PLACEMENT — the only proof that the NPU actually executed
# ─────────────────────────────────────────────────────────────────────────────
#
# Expected runtime line (ground-truth §2), verbatim per @imx95-isp:
#     NeutronDelegate: N nodes delegated out of M nodes with K partitions
# Note the ungrammatical "1 nodes" — that is the library's own wording and a
# useful anchor.
#
# ⚠️ STATUS: confirmed via the native C harness only. NOT re-verified verbatim
# across benchmark_model / tflite_runtime. [INFERRED] that it is caller-stable.
# If the numbers cannot be found, we report UNKNOWN — never success.
#
# ═════════════════════════════════════════════════════════════════════════════
# 🔴 THE SPOOFING BUG THIS ANCHOR EXISTS TO PREVENT (peer review, 2026-08-12)
#
# The first version of this parser grepped for the SHAPE of a placement line and
# not for the word "Neutron":
#       '[0-9]+ +nodes +delegated +out +of +[0-9]+ +nodes'
#
# TFLite's generic delegate-application message has exactly that shape, and
# benchmark_model APPLIES XNNPACK BY DEFAULT:
#       XNNPack delegate: 30 nodes delegated out of 33 nodes with 1 partitions.
#
# So a pure-CPU run printed a matching line, and the gate reported
# "PLACEMENT OK: 30/33" and emitted a [MEASURED] tag. Worse, the parser took
# `tail -1`, so in the realistic ordering — Neutron claims 1 of 310, XNNPACK then
# claims the remaining 280 — the LAST match is XNNPACK's and the converter trap
# was masked entirely. Every one of the three failure modes this file enumerates
# became reportable as healthy.
#
# The fix is two-sided and both halves are required:
#   1. the match must be ANCHORED ON NEUTRON, and
#   2. a foreign placement line with NO Neutron line must REFUSE (exit 7), not
#      merely return "no evidence" — because "another delegate ran your graph" is
#      a different diagnosis with a different fix (--use_xnnpack=false) than
#      "nothing printed".
# ═════════════════════════════════════════════════════════════════════════════

# Shape of any delegate's placement line.
_NEUTRON_PLACEMENT_SHAPE='[0-9]+ +nodes +delegated +out +of +[0-9]+ +nodes'
# The same shape, anchored to the Neutron DELEGATE TOKEN — not merely to the word
# "neutron" somewhere on the line.
#
# Matching bare "neutron.*" was still spoofable: any log whose lines carry a
# neutron-containing prefix (a logger tag, a wrapper echoing the model filename)
# would let a foreign delegate's line through, e.g.
#     model_neutron: XNNPack delegate: 30 nodes delegated out of 33 nodes ...
# — which both parses AS Neutron placement and is excluded from the foreign check,
# i.e. exit 0 on a pure-CPU run. Requiring "neutron" and "delegate" to be adjacent
# (letters/underscore/space/hyphen only between them) closes it: the spoof above has
# ": XNNPack " in between and no longer matches.
#
# Matches: "NeutronDelegate delegate:" (benchmark_model), "NeutronDelegate:"
# (native C harness), "Neutron delegate:", "LiteRtNeutronDelegate".
_NEUTRON_DELEGATE_TOKEN='neutron[[:alnum:]_ -]{0,16}delegate'
_NEUTRON_PLACEMENT_ANCHORED="${_NEUTRON_DELEGATE_TOKEN}.*${_NEUTRON_PLACEMENT_SHAPE}"

NEUTRON_NODES_DELEGATED=""
NEUTRON_NODES_TOTAL=""
NEUTRON_PARTITIONS=""
NEUTRON_PLACEMENT_LINE=""
NEUTRON_FOREIGN_PLACEMENT=""   # a non-Neutron delegate's placement line, if any

# neutron_parse_placement FILE
#   Populate the NEUTRON_* globals from a captured run log.
#   Returns 0 if a NEUTRON placement line was found and parsed, 1 if not.
#   Sets NEUTRON_FOREIGN_PLACEMENT if some OTHER delegate claimed nodes.
neutron_parse_placement() {
    local logfile="${1:?neutron_parse_placement: need a log file}"
    [ -r "$logfile" ] || { log_error "Cannot read run log: ${logfile}"; return 1; }

    NEUTRON_NODES_DELEGATED=""; NEUTRON_NODES_TOTAL=""; NEUTRON_PARTITIONS=""
    NEUTRON_PLACEMENT_LINE=""; NEUTRON_FOREIGN_PLACEMENT=""

    # Any placement line NOT mentioning neutron -> a foreign delegate ran the graph.
    # Foreign = a placement line that does NOT carry the Neutron delegate token.
    # Defined against the ANCHOR, not against the bare word, so the two tests are
    # exact complements and no line can slip between them.
    NEUTRON_FOREIGN_PLACEMENT="$(grep -iE "$_NEUTRON_PLACEMENT_SHAPE" "$logfile" 2>/dev/null \
                                 | grep -ivE "$_NEUTRON_DELEGATE_TOKEN" | tail -1 || true)"

    # Take the LAST Neutron-anchored line specifically.
    NEUTRON_PLACEMENT_LINE="$(grep -iE "$_NEUTRON_PLACEMENT_ANCHORED" "$logfile" 2>/dev/null | tail -1 || true)"

    [ -n "$NEUTRON_PLACEMENT_LINE" ] || return 1

    NEUTRON_NODES_DELEGATED="$(sed -nE 's/.*[^0-9]([0-9]+) +nodes +delegated.*/\1/p' <<<"$NEUTRON_PLACEMENT_LINE" | tail -1)"
    NEUTRON_NODES_TOTAL="$(sed -nE 's/.*out +of +([0-9]+) +nodes.*/\1/p'              <<<"$NEUTRON_PLACEMENT_LINE" | tail -1)"
    NEUTRON_PARTITIONS="$(sed -nE 's/.*with +([0-9]+) +partitions?.*/\1/p'            <<<"$NEUTRON_PLACEMENT_LINE" | tail -1)"

    [ -n "$NEUTRON_NODES_DELEGATED" ] && [ -n "$NEUTRON_NODES_TOTAL" ]
}

# neutron_cma_trap_detected FILE — the soft-fail signature (ground-truth §2.2)
#
# ⚠️ SCOPE, and it matters: this wording is [MEASURED] on the **ONNX Runtime
# Neutron EP** path (@ollama_95_neutron, stock 960 MiB pool). Whether the **TFLite
# delegate** path — which is what bench_npu.sh drives — logs the same text on a
# CMA failure is [UNVERIFIED]. If it logs differently, a real CMA trap will fall
# through to the convert-time diagnosis and get the wrong remedy.
#
# This is an ADVISORY that routes the diagnosis, never the gate. The gate is the
# placement census plus the CmaFree delta, precisely because this string vanishes
# once the neutron DTB is booted.
neutron_cma_trap_detected() {
    grep -qiE 'Neutron hardware init failed|All nodes will be assigned to CPU' "${1:?}" 2>/dev/null
}

# neutron_assert_placement FILE
#   THE GATE. Decide whether the run is a valid NPU measurement, and if it is
#   not, say WHICH failure it is — because the three are fixed in different
#   places and they are indistinguishable by timing.
#
#   exit 0 — healthy, fused. The number may be quoted as [MEASURED].
#   exit 3 — CMA trap        (0 delegated / init-failed)     → fix at RUN time
#   exit 4 — converter trap  (graph never fused)             → fix at CONVERT time
#   exit 5 — no placement evidence at all                    → cannot prove anything
#   exit 7 — A FOREIGN DELEGATE ran the graph (e.g. XNNPACK) → --use_xnnpack=false
neutron_assert_placement() {
    local logfile="${1:?neutron_assert_placement: need a log file}"

    if ! neutron_parse_placement "$logfile"; then
        # A foreign delegate claimed nodes and Neutron printed nothing. This is a
        # CPU run wearing a placement line, and it is the single most dangerous
        # log shape there is, because it looks exactly like success.
        if [ -n "$NEUTRON_FOREIGN_PLACEMENT" ]; then
            log_error "A NON-NEUTRON DELEGATE RAN THIS GRAPH."
            log_error "  ${NEUTRON_FOREIGN_PLACEMENT}"
            log_error ""
            log_error "No Neutron placement line is present, so the NPU did not execute."
            log_error "benchmark_model applies XNNPACK (CPU) BY DEFAULT, and XNNPACK's message"
            log_error "has the SAME SHAPE as the Neutron one — which is why this gate anchors"
            log_error "on the word 'neutron' and why a shape-only match is a CPU run reported"
            log_error "as an NPU measurement."
            log_error "  * Pass --use_xnnpack=false so the CPU delegate cannot claim the graph."
            log_error "  * Then re-check that the model was neutron-converter compiled."
            return 7
        fi

        log_error "NO PLACEMENT EVIDENCE in the run log."
        log_error ""
        log_error "The run may have produced a latency. That latency is NOT a Neutron"
        log_error "measurement, because nothing in the log proves the NPU executed."
        log_error "Absence of proof is reported as failure here, by design:"
        log_error "a plausible number with no placement line is the exact shape of all"
        log_error "three Neutron failure modes (ground-truth §2)."
        if neutron_cma_trap_detected "$logfile"; then
            log_error ""
            log_error "  ...and the CMA-trap signature IS present. See exit 3 guidance below."
            return 3
        fi
        return 5
    fi

    # Neutron DID print a placement line. If a foreign delegate ALSO claimed
    # nodes, say so — that is the realistic converter-trap ordering (Neutron takes
    # 1 of 310, XNNPACK takes the other 280) and it is how the trap gets masked.
    if [ -n "$NEUTRON_FOREIGN_PLACEMENT" ]; then
        log_warn "A foreign delegate ALSO claimed nodes in this run:"
        log_warn "  ${NEUTRON_FOREIGN_PLACEMENT}"
        log_warn "Run with --use_xnnpack=false to attribute the graph unambiguously."
    fi

    log_info "Placement line: ${NEUTRON_PLACEMENT_LINE}"

    # CMA trap: nothing delegated, hardware never initialised.
    if [ "$NEUTRON_NODES_DELEGATED" -eq 0 ] 2>/dev/null; then
        log_error "PLACEMENT: 0 of ${NEUTRON_NODES_TOTAL} nodes delegated — THE NPU DID NOT RUN."
        if neutron_cma_trap_detected "$logfile"; then
            log_error ""
            log_error "DIAGNOSIS: the CMA trap (ground-truth §2.2). NEUTRON_IOCTL_BUFFER_CREATE"
            log_error "could not get contiguous memory, so the graph went to the A55s."
            log_error "This fails SOFT and INTERMITTENTLY — it depends on page-cache state."
            log_error "  * Check CmaFree before AND after: grep -i CmaFree /proc/meminfo"
            log_error "  * Remedy is NOT confirmed. drop_caches is the candidate, [UNVERIFIED]."
            log_error "  * Do not report the latency from this run. It is a CPU number."
            return 3
        fi
        log_error "DIAGNOSIS: nothing was delegated, but the CMA-trap signature is absent."
        log_error "Check that the model was converted for imx95 at all (ground-truth §2.1)."
        return 4
    fi

    # ── Healthy vs converter trap: THE COUNTS DO NOT CLEANLY SEPARATE THEM. ──
    #
    # This surprised us, and it is worth stating plainly rather than hiding in a
    # threshold. Both look like "1 node delegated":
    #
    #   healthy yolov8n   : 1 nodes delegated out of  33   <- backbone FUSED into
    #                                                          one NeutronGraph op;
    #                                                          the ~32 others are the
    #                                                          quant/dequant/NMS tail
    #   converter trap    : 1 nodes delegated out of 310   <- nothing fused at all
    #
    # The delegated COUNT is 1 in both. The discriminator is the TOTAL: a converted
    # model arrives at the runtime already fused, so M is small; a model built by the
    # broken pip converter (microcode 0.0.0) never fused, so M stays large.
    #
    # NEUTRON_FUSED_TOTAL_MAX below is therefore a HEURISTIC, not a measured constant.
    # Basis: fleet-measured healthy graphs are 33-34 nodes; the documented trap case is
    # 310. Everything between is genuinely ambiguous and we say so instead of guessing.
    NEUTRON_FUSED_TOTAL_MAX="${IMX95_NEUTRON_FUSED_TOTAL_MAX:-60}"

    # NOTE: the test is on the TOTAL ALONE, deliberately.
    # An earlier version also required delegated <= 2, which let
    # "5 nodes delegated out of 310" through as healthy — a 98%-CPU run, quotable
    # as [MEASURED]. An unfused total is the trap signature BY ITSELF; how many of
    # the 310 got picked up afterwards is not the question.
    if [ "$NEUTRON_NODES_TOTAL" -gt "$NEUTRON_FUSED_TOTAL_MAX" ] 2>/dev/null; then
        log_error "PLACEMENT: ${NEUTRON_NODES_DELEGATED} of ${NEUTRON_NODES_TOTAL} nodes delegated."
        log_error ""
        log_error "CONSISTENT WITH THE CONVERTER TRAP (ground-truth §2.1) — the graph does"
        log_error "not look fused. A converted model reaches the runtime with its conv"
        log_error "backbone already collapsed into ONE NeutronGraph op, so the total node"
        log_error "count is small (fleet-measured: 33-34 for yolov8). ${NEUTRON_NODES_TOTAL} is not that."
        log_error ""
        log_error "⚠️ This is a HEURISTIC on the node total, not proof. Confirm it by either:"
        log_error "  * checking the converter output for microcode version 0.0.0 (the tell), or"
        log_error "  * re-converting with the STANDALONE eIQ Neutron SDK CLI 3.1.3:"
        log_error "      neutron-converter --input model_int8.tflite --target imx95 --output out.tflite"
        log_error "If this model legitimately has >${NEUTRON_FUSED_TOTAL_MAX} nodes after fusion, raise"
        log_error "IMX95_NEUTRON_FUSED_TOTAL_MAX and re-run — but check the converter first."
        log_error ""
        log_error "Either way: do not report this run's latency. It is mostly a CPU number."
        return 4
    fi

    # Multi-partition = delegate fragmentation. The dossier's own e2e bottleneck
    # table names this as what bounds the deployed number, so it is not a warning:
    # warn-and-continue is precisely the pattern this repo's contract forbids.
    if [ "${NEUTRON_PARTITIONS:-1}" -gt 1 ] 2>/dev/null; then
        if [ "${IMX95_NEUTRON_ALLOW_FRAGMENTED:-0}" = "1" ]; then
            log_warn "${NEUTRON_PARTITIONS} partitions — fragmented, allowed by"
            log_warn "IMX95_NEUTRON_ALLOW_FRAGMENTED=1. Carry that caveat with the number."
        else
            log_error "PLACEMENT: ${NEUTRON_PARTITIONS} partitions — the graph crossed the"
            log_error "NPU/CPU boundary more than once (delegate fragmentation)."
            log_error ""
            log_error "A healthy i.MX95 CNN shows ONE NeutronGraph. Only DEPTH_TO_SPACE may"
            log_error "legitimately fall to the A55 [MEASURED, @imx95-isp]; anything else in the"
            log_error "fallback set is a TOPOLOGY REGRESSION, not a tuning knob (ground-truth §2.4)."
            log_error "Fragmentation is also what bounds the deployed e2e number, so a latency"
            log_error "from this run does not describe the model you think you are shipping."
            log_error "  * Inspect the op list; check for a non-DEPTH_TO_SPACE fallback."
            log_error "  * To measure anyway, set IMX95_NEUTRON_ALLOW_FRAGMENTED=1 — and carry"
            log_error "    the caveat with every number you quote from it."
            return 4
        fi
    fi

    log_info "PLACEMENT OK: ${NEUTRON_NODES_DELEGATED}/${NEUTRON_NODES_TOTAL} nodes, ${NEUTRON_PARTITIONS:-1} partition(s)."
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# CMA — a precondition for EVERY Neutron measurement on the delegate path
# ─────────────────────────────────────────────────────────────────────────────
#
# ⚠️ WHICH POOL: the dossier says the dedicated 4 GiB neutron_memory pool retires
# the CMA-starvation hazard *entirely* (it is page-cache-immune). Our claim that
# the TFLite delegate path "still draws from the 960 MiB linux,cma" is
# [UNVERIFIED] — it follows from linux,cma being left at 960 MiB, but nobody has
# measured which pool the delegate actually allocates from. Keeping the check is
# the conservative choice; asserting the reason would not be.

# ⭐ CmaFree IS A SECOND, INDEPENDENT PROOF THAT THE NPU EXECUTED.
#
# @imx95-isp, [MEASURED]: a real offload DROPS CmaFree (~2 MB); a silent CPU
# fallback does not move it at all. That is enormously valuable because it does
# not depend on ANY log wording — which is exactly the weakness of the error
# string (§2.2: the string vanishes once the neutron DTB is booted, so a detector
# keyed on it passes on a healthy board).
#
# ⚠️ THE RULE IS ABOUT THE *LIFETIME OF THE INTERPRETER CONTEXT*, NOT ABOUT
#    "BEFORE/AFTER" VS "DURING". Getting this wrong silently disables the check.
#
# @imx95-isp measured the drop with a plain before/after snapshot, and it worked
# for them. It does NOT work here, and the difference is not the sampling style —
# it is WHAT IS ALIVE at the moment you sample:
#
#   * a PERSISTENT harness (their native C loop) holds the delegate and its CMA
#     buffer live across the whole timed region, so any snapshot taken inside that
#     lifetime sees the pool down. before/after-within-lifetime is fine.
#   * a ONE-SHOT tool (benchmark_model) allocates at init and FREES AT EXIT, so by
#     the time the process returns, CmaFree is already back at baseline. A
#     snapshot taken around the process reads "no drop" ON A PERFECTLY HEALTHY RUN
#     — and we would conclude silent CPU fallback and refuse a good measurement.
#
# ⇒ General rule, safe for both: SAMPLE WHILE THE INTERPRETER/EP CONTEXT IS ALIVE
#   AND KEEP THE MINIMUM. Continuous in-run sampling is the safe default; the
#   persistent-harness before/after is a special case of it, not an alternative.

_NEUTRON_CMA_FREE_BASE=""
_NEUTRON_CMA_WATCH_PID=""
_NEUTRON_CMA_WATCH_FILE=""

neutron_cma_snapshot_before() {
    _NEUTRON_CMA_FREE_BASE="$(cma_free_mb 2>/dev/null || echo "")"
    [ -n "$_NEUTRON_CMA_FREE_BASE" ] &&
        log_debug "CmaFree baseline: ${_NEUTRON_CMA_FREE_BASE} MB"
    return 0
}

# neutron_cma_watch_start — begin sampling CmaFree in the background.
neutron_cma_watch_start() {
    [ -r /proc/meminfo ] || return 0
    _NEUTRON_CMA_WATCH_FILE="$(mktemp)" || return 0
    (
        while :; do
            awk '/^CmaFree:/ {print $2}' /proc/meminfo >> "$_NEUTRON_CMA_WATCH_FILE" 2>/dev/null
            sleep 0.2
        done
    ) &
    _NEUTRON_CMA_WATCH_PID=$!
    log_debug "CmaFree sampler pid ${_NEUTRON_CMA_WATCH_PID}"
    return 0
}

# neutron_cma_watch_stop — stop the sampler and REAP IT, printing proof.
#   `kill` then `kill -9` after a grace period: a TERM a wedged child never
#   services is a request, not a stop, and an orphaned sampler is a corpse that
#   silently biases the next session's measurements.
neutron_cma_watch_stop() {
    [ -n "$_NEUTRON_CMA_WATCH_PID" ] || return 0
    kill "$_NEUTRON_CMA_WATCH_PID" 2>/dev/null || true
    local i=0
    while kill -0 "$_NEUTRON_CMA_WATCH_PID" 2>/dev/null && [ "$i" -lt 10 ]; do
        sleep 0.1; i=$((i+1))
    done
    if kill -0 "$_NEUTRON_CMA_WATCH_PID" 2>/dev/null; then
        kill -9 "$_NEUTRON_CMA_WATCH_PID" 2>/dev/null || true
        log_debug "CmaFree sampler ${_NEUTRON_CMA_WATCH_PID} needed SIGKILL"
    fi
    wait "$_NEUTRON_CMA_WATCH_PID" 2>/dev/null || true
    _NEUTRON_CMA_WATCH_PID=""
    return 0
}

# neutron_cma_execution_evidence — did CmaFree move enough to prove an allocation?
#   0 = a drop consistent with a real NPU allocation was observed
#   1 = no meaningful drop  (suspicious: consistent with a silent CPU fallback)
#   2 = cannot tell (no samples / no baseline) -> caller must report UNKNOWN
NEUTRON_CMA_MIN_MB=""
NEUTRON_CMA_DROP_MB=""
neutron_cma_execution_evidence() {
    local min_kb min_mb
    [ -n "$_NEUTRON_CMA_FREE_BASE" ] || return 2
    [ -n "$_NEUTRON_CMA_WATCH_FILE" ] && [ -s "$_NEUTRON_CMA_WATCH_FILE" ] || return 2

    min_kb="$(sort -n "$_NEUTRON_CMA_WATCH_FILE" | head -1)"
    [ -n "$min_kb" ] || return 2
    min_mb=$(( min_kb / 1024 ))
    NEUTRON_CMA_MIN_MB="$min_mb"
    NEUTRON_CMA_DROP_MB=$(( _NEUTRON_CMA_FREE_BASE - min_mb ))

    rm -f "$_NEUTRON_CMA_WATCH_FILE" 2>/dev/null || true
    _NEUTRON_CMA_WATCH_FILE=""

    # Threshold: the observed real-offload drop is ~2 MB. 1 MB is the smallest
    # move we can distinguish given MB granularity. HEURISTIC, not a constant.
    [ "$NEUTRON_CMA_DROP_MB" -ge "${IMX95_NEUTRON_CMA_MIN_DROP_MB:-1}" ] 2>/dev/null
}

# neutron_cma_check_after — legacy hazard check: did the pool collapse and stay down?
neutron_cma_check_after() {
    local after; after="$(cma_free_mb 2>/dev/null || echo "")"
    [ -n "$_NEUTRON_CMA_FREE_BASE" ] && [ -n "$after" ] || return 0
    log_info "CmaFree: ${_NEUTRON_CMA_FREE_BASE} MB (baseline) -> ${after} MB (after)"
    if [ "$after" -lt $(( _NEUTRON_CMA_FREE_BASE / 2 )) ] 2>/dev/null; then
        log_warn "CmaFree more than halved and did NOT recover — this run is SUSPECT."
        log_warn "A run that started with a healthy pool and ended with a collapsed one is"
        log_warn "the co-residence/memory-pressure case the CMA trap lives in. It may also"
        log_warn "mean something leaked a CMA buffer; check before trusting the next run."
    fi
    return 0
}
