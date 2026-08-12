#!/bin/bash
# skills/imx95-package/scripts/install_pkg.sh
#
# Installs a package using the detected package manager (apt or opkg).
# Checks rootfs is read-write before attempting install.
# Verifies installation success.
#
# Usage: install_pkg.sh <package-name> [--yes]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <package-name> [--yes]

Arguments:
  package-name   Name of the package to install

Options:
  --yes          Skip confirmation prompt
  -h, --help     Show this help

Examples:
  $(basename "$0") python3-numpy
  $(basename "$0") gpiod --yes
  $(basename "$0") v4l-utils
EOF
}

if [[ $# -lt 1 ]] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage; exit 0
fi

PKG_NAME="$1"
SKIP_CONFIRM=0
[[ "${2:-}" = "--yes" ]] && SKIP_CONFIRM=1

# ---------------------------------------------------------------------------
# Detect package manager
# ---------------------------------------------------------------------------
# shellcheck source=skills/imx95-package/scripts/detect_pkg_manager.sh
source "${SCRIPT_DIR}/detect_pkg_manager.sh" --quiet

if [ -z "${PKG_MANAGER}" ]; then
    die "No package manager found. Cannot install packages."
fi

# ---------------------------------------------------------------------------
# Check rootfs is writable
# ---------------------------------------------------------------------------
if [ "${ROOTFS_RW}" = "0" ]; then
    log_error "Root filesystem is read-only. Cannot install packages."
    log_error "To enable writes: mount -o remount,rw /"
    log_error "Note: changes are lost on reboot unless the image is rebuilt."
    exit 1
fi

# ---------------------------------------------------------------------------
# Check if already installed
# ---------------------------------------------------------------------------
ALREADY_INSTALLED=0
case "${PKG_MANAGER}" in
    apt)
        dpkg -l "${PKG_NAME}" &>/dev/null 2>&1 && \
            dpkg -l "${PKG_NAME}" | grep -q "^ii" && ALREADY_INSTALLED=1 || true
        ;;
    opkg)
        opkg list-installed 2>/dev/null | grep -q "^${PKG_NAME} " && ALREADY_INSTALLED=1 || true
        ;;
esac

if [ "${ALREADY_INSTALLED}" = "1" ]; then
    log_info "Package '${PKG_NAME}' is already installed."
    exit 0
fi

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
if [ "${SKIP_CONFIRM}" = "0" ]; then
    echo ""
    echo "About to install package:"
    echo "  Package manager : ${PKG_MANAGER}"
    echo "  Package         : ${PKG_NAME}"
    echo ""
    echo -n "Confirm? [y/N] "
    read -r answer
    [[ ! "${answer}" =~ ^[Yy]$ ]] && { log_info "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
log_info "Installing '${PKG_NAME}' via ${PKG_MANAGER}..."

case "${PKG_MANAGER}" in
    apt)
        # Update index if it's stale (older than 1 hour)
        APT_LISTS_DIR="/var/lib/apt/lists"
        if [ -d "${APT_LISTS_DIR}" ]; then
            LISTS_AGE=$(( $(date +%s) - $(stat -c %Y "${APT_LISTS_DIR}" 2>/dev/null || echo 0) ))
            if [ "${LISTS_AGE}" -gt 3600 ]; then
                log_info "Updating apt package index..."
                apt-get update -qq 2>/dev/null || log_warn "apt-get update failed — using cached index"
            fi
        fi
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKG_NAME}" || {
            log_error "apt-get install failed for '${PKG_NAME}'"
            log_error "Try: apt-cache search ${PKG_NAME}"
            exit 1
        }
        ;;
    opkg)
        opkg update 2>/dev/null || log_warn "opkg update failed — using cached index"
        opkg install "${PKG_NAME}" || {
            log_error "opkg install failed for '${PKG_NAME}'"
            log_error "Try: opkg find *${PKG_NAME}*"
            exit 1
        }
        ;;
    *)
        die "Unsupported package manager: ${PKG_MANAGER}"
        ;;
esac

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
INSTALL_OK=0
case "${PKG_MANAGER}" in
    apt)
        dpkg -l "${PKG_NAME}" 2>/dev/null | grep -q "^ii" && INSTALL_OK=1 || true
        ;;
    opkg)
        opkg list-installed 2>/dev/null | grep -q "^${PKG_NAME} " && INSTALL_OK=1 || true
        ;;
esac

if [ "${INSTALL_OK}" = "1" ]; then
    log_info "Package '${PKG_NAME}' installed successfully."
else
    log_warn "Package manager reported success but '${PKG_NAME}' not found in installed list."
    log_warn "The package may have a different name in the installed database."
fi
