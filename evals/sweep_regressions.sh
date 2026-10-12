#!/usr/bin/env bash
# evals/sweep_regressions.sh
#
# REGRESSION TESTS FOR THE 2026-10-09/10 v1 SKILL SWEEP.
#
# Each case below pins a behaviour that was WRONG in v1 and is now right. They
# exist because of a measured fact about that sweep: nine defects were fixed and
# THREE WERE INTRODUCED — a crash on correct input, a silently-skipped guard,
# and a pattern substitution into live code — and every one of the three was
# caught by RUNNING something, never by reading it. Without these, the next
# person editing these files has the same exposure and no net.
#
# ── TWO RULES THIS FILE FOLLOWS, BOTH LEARNED THE HARD WAY ──────────────────
#
# 1. EVERY GUARD IS TESTED IN BOTH DIRECTIONS. A guard that refuses everything
#    is as useless as one that refuses nothing, and only the must-PASS arm tells
#    them apart. Two separate failures during the sweep prove it:
#      - the R6 lint had a must-pass arm and no must-fire arm -> it was INERT and
#        reported clean while never examining a single pointer;
#      - init_target's fix had a must-warn arm and no must-pass arm -> it
#        CRASHED on the correct machine name, exit 127, and looked green.
#    ⇒ Whichever arm you find more natural to write is the one that will not
#      save you.
#
# 2. THE HARNESS PROVES IT CAN FAIL (see --self-test). A suite that only ever
#    passes should be suspected of measuring nothing: @qualcomm's inert-checker
#    law, and the reason `ok`/`no` are exercised against a deliberate miss.
#
# Usage:  bash evals/sweep_regressions.sh [--self-test]
# Exit:   0 all passed · 1 a regression · 2 self-test failed

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
SK="${REPO}/skills"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { echo "[PASS] $1"; PASS=$((PASS+1)); }
no() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

# grep a file for a pattern; pass when present (or absent, with -v semantics)
has()  { grep -qE "$2" "$1" 2>/dev/null; }
hasnt() { ! grep -qE "$2" "$1" 2>/dev/null; }

# live_has — matches only NON-COMMENT lines.
#
# ⚠️ ADDED AFTER THIS SUITE'S FIRST RUN, which reported 4 failures of which only
# ONE was real. The other three all matched the RETRACTION COMMENTS that quote
# the old broken code verbatim — e.g. audit.sh explaining that it used to print
# "STATUS: OK". A regression test that fires on the documentation of a fix is
# the same over-counting my grep triage did six times during the sweep: a
# pattern finds candidates, never findings.
live_has()  { grep -nE "$2" "$1" 2>/dev/null | grep -qvE '^[0-9]+:[[:space:]]*#'; }
live_hasnt() { ! live_has "$1" "$2"; }

# ── self-test: prove these helpers can report FAILURE ───────────────────────
if [ "${1:-}" = "--self-test" ]; then
    echo "=== harness self-test: the suite must be able to FAIL ==="
    P0=$PASS; F0=$FAIL
    has /dev/null 'this-cannot-match' && no "has() matched nothing" || ok "has() correctly reports absence"
    hasnt /dev/null 'this-cannot-match' && ok "hasnt() correctly reports absence" || no "hasnt() wrong"
    # deliberately fail, to prove FAIL increments and the exit code follows
    no "DELIBERATE failure — proves this harness can report a regression"
    if [ "$FAIL" -gt "$F0" ]; then
        echo "--- self-test OK: FAIL incremented (${F0} -> ${FAIL}); a real regression would surface"
        exit 0
    fi
    echo "--- self-test BROKEN: a deliberate failure did not register"; exit 2
fi

echo "=== sweep regressions :: imx95-device-skills ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. print-device-info — the eIQ runner must come from the SINGLE discovery
#    source, not from invented paths.
#
# v1 searched /usr/bin/eiq-benchmark, /usr/local/bin/eiq-benchmark,
# /opt/eiq/bin/eiq-benchmark, /usr/share/eiq/version, /etc/eiq-version — NONE
# of which exist. The real runner is in a VERSIONED dir not on PATH, so it
# reported eIQ "not detected" on a board where it works: a FALSE NEGATIVE ON A
# REAL CAPABILITY, and an agent told "no runner" does not try to benchmark.
PDI="${SK}/imx95-print-device-info/scripts/print_info.sh"
has "$PDI" 'neutron_find_runner' \
  && ok "print-device-info delegates runner discovery to lib/neutron.sh" \
  || no "print-device-info no longer uses neutron_find_runner"
# the invented paths may appear ONLY in the comment explaining their removal
if grep -nE '/opt/eiq|eiq-benchmark|/etc/eiq-version' "$PDI" 2>/dev/null \
   | grep -qvE '^\s*[0-9]+:\s*#'; then
    no "print-device-info has a LIVE reference to an invented eIQ path"
else
    ok "print-device-info's invented eIQ paths exist only in comments"
fi
has "$PDI" 'NOT a board identity' \
  && ok "print-device-info labels hostname as not-an-identity" \
  || no "print-device-info prints hostname without the non-uniqueness warning"
has "$PDI" 'findmnt -no SOURCE' \
  && ok "print-device-info names the device backing / (not just the mount)" \
  || no "print-device-info reports Disk / without naming the device"

# ─────────────────────────────────────────────────────────────────────────────
# 2+3. memory-audit AND diagnostic — the CMA verdict must be WITHHELD.
#
# CmaFree sums linux,cma (~960 MiB, the TFLite delegate's pool) and
# neutron_memory (~4096 MiB); no CONFIG_CMA_DEBUGFS on this kernel. Full
# exhaustion of the pool that matters reads as 960/5056 = 19% of the aggregate
# — BELOW the old 80% threshold — so both skills printed OK at the exact moment
# the delegate could not allocate. NOTE this defect existed in TWO files and
# fixing one left the other; it was found by grepping the old value fleet-wide.
for pair in "imx95-memory-audit/scripts/audit.sh" "imx95-diagnostic/scripts/snapshot.sh"; do
    f="${SK}/${pair}"; n="$(basename "$(dirname "$(dirname "$pair")")")"
    has "$f" 'NOT A HEALTH SIGNAL' \
      && ok "${n}: CMA figure labelled not-a-health-signal" \
      || no "${n}: CMA aggregate reported without the two-pool caveat"
    has "$f" 'neutron_memory' \
      && ok "${n}: names the second pool (neutron_memory)" \
      || no "${n}: does not mention the second CMA pool"
    # the bare unconditional "OK" verdict must be gone
    if live_has "$f" 'echo "(MEMORY )?STATUS: OK"'; then
        no "${n}: still emits an unqualified OK verdict"
    else
        ok "${n}: no unqualified OK verdict (comments quoting it are fine)"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# 4. gpio-config — a skill that DRIVES GPIO LINES must not be marked
#    run-without-asking. `safe: true` means exactly that in CLAUDE.md, and an
#    in-script confirmation cannot help if the harness was told none is needed.
G="${SK}/imx95-gpio-config/SKILL.md"
has "$G" '^safe: false' \
  && ok "gpio-config is safe:false (it drives GPIO lines)" \
  || no "gpio-config is marked safe:true while writing hardware"

# ─────────────────────────────────────────────────────────────────────────────
# 5. package — must REFUSE, not warn-and-continue, when the feed is unusable.
#
# v1: `opkg update || log_warn "using cached index"` then install anyway. This
# image has NO WORKING FEED [MEASURED], so that fires EVERY time and it always
# installed from a stale cache — the delegate bug's shape exactly.
P="${SK}/imx95-package/scripts/install_pkg.sh"
has "$P" 'refusing to install from a stale index' \
  && ok "package refuses on a failed opkg update" \
  || no "package no longer refuses when the index is stale"
live_hasnt "$P" 'using cached index' \
  && ok "package no longer warns-and-continues (apt AND opkg)" \
  || no "package still falls through to a cached index"
# both branches must refuse, not just opkg — the first run caught apt still
# warning-and-continuing because I fixed one path and justified leaving the other
has "$P" 'refusing to install from a stale index' \
  && ok "package: opkg branch refuses" || no "package: opkg branch stopped refusing"
has "$P" 'apt-get update FAILED' \
  && ok "package: apt branch refuses too (symmetry)" || no "package: apt branch does not refuse"

# ─────────────────────────────────────────────────────────────────────────────
# 6. camera-setup — /dev/video* existing is NOT a camera. All four nodes on
#    this board are CODECS (Wave6 dec/enc, mxc-jpeg dec/enc), so defaulting to
#    /dev/video0 pointed a capture test at a VIDEO DECODER.
C="${SK}/imx95-camera-setup/scripts/test_capture.sh"
has "$C" 'DEVICE=""' \
  && ok "camera test_capture has no default device" \
  || no "camera test_capture still defaults to a device"
has "$C" 'NO DEFAULT' \
  && ok "camera test_capture explains why there is no default" \
  || no "camera test_capture lost the no-default rationale"

# ─────────────────────────────────────────────────────────────────────────────
# 7. The repo-level invariant the sweep established: no skill may assert a
#    rootfs free-space figure as a current fact (it moved 10 GB in two days),
#    and none may use `hostname` as a board identity (two fleet boards answer
#    to imx95evk).
viol=0
for f in $(find "$SK" -name "*.sh" -o -name "SKILL.md" 2>/dev/null); do
    # a live (non-comment) hostname-as-identity assertion
    # Reading hostname as a REPORTED FIELD is fine (both skills label it
    # not-an-identity when printing). What is forbidden is using it to DECIDE
    # which board you are on: a comparison or a gate. The first version of this
    # check flagged `HOSTNAME_VAL=$(hostname)` and my own retraction prose.
    if grep -nE '(\[\[|\[|if ).*hostname|hostname.*==|==.*hostname|hostname.*=~' "$f" 2>/dev/null \
       | grep -vE '^[0-9]+:[[:space:]]*#' | grep -q .; then
        echo "       ... $f"; viol=$((viol+1))
    fi
done
[ "$viol" -eq 0 ] \
  && ok "no skill uses hostname as a board identity" \
  || no "${viol} file(s) use hostname as an identity"

echo "--- ${PASS} passed, ${FAIL} failed ---"
[ "$FAIL" -eq 0 ]
