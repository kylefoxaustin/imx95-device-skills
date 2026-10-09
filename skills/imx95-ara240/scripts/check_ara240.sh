#!/usr/bin/env bash
# skills/imx95-ara240/scripts/check_ara240.sh
#
# ARA240 presence check. It reports PRESENCE. It never reports AVAILABILITY.
#
# Why: an owner audit across 500 confirmed inferences measured that NO host-side
# signal distinguishes a busy ARA240 from an idle one. The uiodma lsmod use-count
# stays 0 throughout, because the persistent proxy_ara240 daemon mmaps the PCI BAR
# at idle AND during inference. `:5000` ESTAB and BAR-fuser were equally flat.
#
# A previous fleet check reported "✅ free" on a fully-busy board. That is the
# specific failure this script exists to not repeat. "I cannot tell" is the honest
# answer for an opaque resource, and it is the answer we print.
#
# Exit codes:
#   0  present (occupancy deliberately NOT asserted)
#   1  not present / runtime missing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/lib/neutron.sh"   # for prov()

ARA_PCI_ID="1e58:0002"
ARA_RT_DIR="/usr/share/rt-sdk-ara240_2.1.1"
ARA_SOCK="/var/run/proxy.sock"

log_section "Kinara ARA240 (M.2) — presence"

RC=0

# ── PCI enumeration ──────────────────────────────────────────────────────────
PCI_LINE=""
if command -v lspci >/dev/null 2>&1; then
    PCI_LINE="$(lspci -nn 2>/dev/null | grep -i "${ARA_PCI_ID}" || true)"
fi
if [ -n "$PCI_LINE" ]; then
    prov MEASURED "PCI device" "${ARA_PCI_ID}" "$(echo "$PCI_LINE" | cut -c1-12)"
else
    log_error "ARA240 not enumerated on PCI (${ARA_PCI_ID})."
    log_error "This is an INSTANCE fact: the card being seated is true of a specific"
    log_error "physical board, not of 'an i.MX95'. If the M.2 was swapped, that is why."
    RC=1
fi

# ── Driver ───────────────────────────────────────────────────────────────────
if lsmod 2>/dev/null | grep -q '^uiodma'; then
    USECOUNT="$(lsmod | awk '$1=="uiodma"{print $3}')"
    prov MEASURED "uiodma module" "loaded" "use-count ${USECOUNT}"
    log_warn "⚠️  That use-count is NOT an occupancy signal. It reads 0 during a fully"
    log_warn "    busy 500-inference run — the daemon holds the BAR at idle too."
else
    log_warn "uiodma not in lsmod (may be built in)."
fi

# ── Runtime + daemon ─────────────────────────────────────────────────────────
if [ -x "${ARA_RT_DIR}/nnapp/nnapp" ]; then
    prov MEASURED "nnapp runtime" "present" "${ARA_RT_DIR}"
else
    log_error "Kinara runtime not found at ${ARA_RT_DIR}/nnapp/nnapp"
    RC=1
fi

DAEMON_PID=""
for p in /proc/[0-9]*; do
    pid="${p#/proc/}"
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    case "$exe" in *kinara_main*|*proxy_ara240*) DAEMON_PID="$pid"; break ;; esac
done
if [ -n "$DAEMON_PID" ]; then
    # Resolve via /proc/PID/exe, never `comm` — comm truncates at 15 bytes and will
    # hand you a different program's name.
    prov MEASURED "proxy daemon" "pid ${DAEMON_PID}" "$(readlink "/proc/${DAEMON_PID}/exe" 2>/dev/null)"
else
    log_warn "proxy_ara240 daemon not found — nnapp clients will have nothing to talk to."
fi

[ -S "$ARA_SOCK" ] && prov MEASURED "proxy socket" "present" "$ARA_SOCK" \
                   || log_warn "proxy socket ${ARA_SOCK} absent."

# ── THE REFUSAL ──────────────────────────────────────────────────────────────
echo
log_warn "⚠️  ARA240 occupancy CANNOT BE DETERMINED FROM THE HOST — measured, not assumed."
log_warn "    No host-side signal (uiodma refcount, :5000 ESTAB, BAR-fuser) distinguishes"
log_warn "    idle from busy. This script therefore does NOT tell you the device is free,"
log_warn "    and you must not infer it from a clean-looking output above."
log_warn "    Treat as OPAQUE: a dead owner means QUARANTINE, never auto-reap."
echo
prov UNKNOWN "ARA240 occupancy" "" "no host-side signal exists (500-inference audit)"

exit "$RC"
