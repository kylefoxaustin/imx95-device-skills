#!/bin/bash
# skills/imx95-package/scripts/detect_pkg_manager.sh
#
# Detects which package manager is available on this board.
# Exports PKG_MANAGER ("apt" or "opkg") and PKG_MANAGER_PATH.
# Checks rootfs read/write state.
#
# Usage: detect_pkg_manager.sh [--quiet]
# Source this file to get PKG_MANAGER exported:
#   source skills/imx95-package/scripts/detect_pkg_manager.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

QUIET=0
[[ "${1:-}" = "--quiet" ]] && QUIET=1
[[ "${1:-}" =~ ^(-h|--help)$ ]] && { echo "Usage: $(basename "$0") [--quiet]"; exit 0; }

# ---------------------------------------------------------------------------
# Detect package manager
# ---------------------------------------------------------------------------
PKG_MANAGER=""
PKG_MANAGER_PATH=""

if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
    PKG_MANAGER_PATH=$(command -v apt-get)
elif command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    PKG_MANAGER_PATH=$(command -v apt)
elif command -v opkg &>/dev/null; then
    PKG_MANAGER="opkg"
    PKG_MANAGER_PATH=$(command -v opkg)
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    PKG_MANAGER_PATH=$(command -v dnf)
elif command -v rpm &>/dev/null; then
    PKG_MANAGER="rpm"
    PKG_MANAGER_PATH=$(command -v rpm)
fi

export PKG_MANAGER
export PKG_MANAGER_PATH

if [ -z "${PKG_MANAGER}" ]; then
    [ "${QUIET}" = "0" ] && log_error "No supported package manager found (apt, opkg, dnf)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Check rootfs read/write state
# ---------------------------------------------------------------------------
ROOTFS_RW=0
if mount 2>/dev/null | grep -E "^[^ ]+ on / " | grep -q '\brw\b'; then
    ROOTFS_RW=1
fi
export ROOTFS_RW

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [ "${QUIET}" = "0" ]; then
    printf "%-20s: %s (%s)\n" "Package manager" "${PKG_MANAGER}" "${PKG_MANAGER_PATH}"
    if [ "${ROOTFS_RW}" = "1" ]; then
        printf "%-20s: %s\n" "Root filesystem" "read-write (package install OK)"
    else
        printf "%-20s: %s\n" "Root filesystem" "READ-ONLY — package install will fail"
        log_warn "Root filesystem is read-only."
        log_warn "To enable writes: mount -o remount,rw /"
        log_warn "Note: changes are lost on reboot unless image is rebuilt."
    fi

    # Show configured feeds for opkg
    if [ "${PKG_MANAGER}" = "opkg" ] && [ -d /etc/opkg ]; then
        echo ""
        echo "opkg feeds:"
        grep -h "^src" /etc/opkg/*.conf 2>/dev/null | sed 's/^/  /' || \
            echo "  (no feeds configured — check /etc/opkg/)"
    fi

    # Show apt sources for apt
    if [ "${PKG_MANAGER}" = "apt" ] && [ -f /etc/apt/sources.list ]; then
        echo ""
        echo "apt sources:"
        grep -v "^#\|^$" /etc/apt/sources.list 2>/dev/null | head -5 | sed 's/^/  /' || \
            echo "  (empty sources.list)"
    fi
fi
