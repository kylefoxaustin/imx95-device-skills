#!/bin/bash
# skills/imx95-package/scripts/remove_pkg.sh
#
# Removes a package using the detected package manager (apt or opkg).
# Checks the package is actually installed before attempting removal.
# Requires confirmation before proceeding.
#
# Usage: remove_pkg.sh <package-name> [--yes]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <package-name> [--yes]

Arguments:
  package-name   Name of the package to remove

Options:
  --yes          Skip confirmation prompt
  -h, --help     Show this help

Examples:
  $(basename "$0") python3-numpy
  $(basename "$0") gpiod --yes
EOF
}

if [[ $# -lt 1 ]] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage; exit 0
fi

PKG_NAME="$1"
SKIP_CONFIRM=0
[[ "${2:-}" = "--yes" ]] && SKIP_CONFIRM=1

# Detect package manager
# shellcheck source=skills/imx95-package/scripts/detect_pkg_manager.sh
source "${SCRIPT_DIR}/detect_pkg_manager.sh" --quiet

[ -z "${PKG_MANAGER}" ] && die "No package manager found."

# Check rootfs writable
if [ "${ROOTFS_RW}" = "0" ]; then
    log_error "Root filesystem is read-only. Cannot remove packages."
    log_error "To enable writes: mount -o remount,rw /"
    exit 1
fi

# Check if installed
IS_INSTALLED=0
case "${PKG_MANAGER}" in
    apt)  dpkg -l "${PKG_NAME}" 2>/dev/null | grep -q "^ii" && IS_INSTALLED=1 || true ;;
    opkg) opkg list-installed 2>/dev/null | grep -q "^${PKG_NAME} " && IS_INSTALLED=1 || true ;;
esac

if [ "${IS_INSTALLED}" = "0" ]; then
    log_info "Package '${PKG_NAME}' is not installed — nothing to remove."
    exit 0
fi

# Confirmation
if [ "${SKIP_CONFIRM}" = "0" ]; then
    echo ""
    echo "About to remove package:"
    echo "  Package manager : ${PKG_MANAGER}"
    echo "  Package         : ${PKG_NAME}"
    echo ""
    echo -n "Confirm removal? [y/N] "
    read -r answer
    [[ ! "${answer}" =~ ^[Yy]$ ]] && { log_info "Aborted."; exit 0; }
fi

log_info "Removing '${PKG_NAME}' via ${PKG_MANAGER}..."

case "${PKG_MANAGER}" in
    apt)
        DEBIAN_FRONTEND=noninteractive apt-get remove -y "${PKG_NAME}" || {
            log_error "apt-get remove failed for '${PKG_NAME}'"
            exit 1
        }
        ;;
    opkg)
        opkg remove "${PKG_NAME}" || {
            log_error "opkg remove failed for '${PKG_NAME}'"
            exit 1
        }
        ;;
    *)
        die "Unsupported package manager: ${PKG_MANAGER}"
        ;;
esac

# Verify removal
STILL_INSTALLED=0
case "${PKG_MANAGER}" in
    apt)  dpkg -l "${PKG_NAME}" 2>/dev/null | grep -q "^ii" && STILL_INSTALLED=1 || true ;;
    opkg) opkg list-installed 2>/dev/null | grep -q "^${PKG_NAME} " && STILL_INSTALLED=1 || true ;;
esac

if [ "${STILL_INSTALLED}" = "0" ]; then
    log_info "Package '${PKG_NAME}' removed successfully."
else
    log_warn "Package '${PKG_NAME}' may still be installed — check manually."
fi
