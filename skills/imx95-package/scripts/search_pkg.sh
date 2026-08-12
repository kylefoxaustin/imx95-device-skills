#!/bin/bash
# skills/imx95-package/scripts/search_pkg.sh
#
# Searches for packages matching a term using apt-cache or opkg find.
# Also checks if the package is currently installed.
#
# Usage: search_pkg.sh <search-term>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <search-term>

Searches for packages matching the given term.
Also shows whether matching packages are currently installed.

Examples:
  $(basename "$0") numpy
  $(basename "$0") gpiod
  $(basename "$0") v4l
EOF
}

if [[ $# -lt 1 ]] || [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    usage; exit 0
fi

SEARCH_TERM="$1"

# Detect package manager
# shellcheck source=skills/imx95-package/scripts/detect_pkg_manager.sh
source "${SCRIPT_DIR}/detect_pkg_manager.sh" --quiet

[ -z "${PKG_MANAGER}" ] && die "No package manager found."

log_info "Searching for '${SEARCH_TERM}' via ${PKG_MANAGER}..."
echo ""

case "${PKG_MANAGER}" in
    apt)
        echo "=== apt-cache search results ==="
        apt-cache search "${SEARCH_TERM}" 2>/dev/null | head -30 | \
        while IFS= read -r line; do
            pkg_name=$(echo "${line}" | cut -d' ' -f1)
            # Mark if installed
            if dpkg -l "${pkg_name}" 2>/dev/null | grep -q "^ii"; then
                echo "  [INSTALLED] ${line}"
            else
                echo "  ${line}"
            fi
        done || echo "  (no results)"
        ;;
    opkg)
        echo "=== opkg find results ==="
        opkg find "*${SEARCH_TERM}*" 2>/dev/null | head -30 | \
        while IFS= read -r line; do
            pkg_name=$(echo "${line}" | cut -d' ' -f1)
            if opkg list-installed 2>/dev/null | grep -q "^${pkg_name} "; then
                echo "  [INSTALLED] ${line}"
            else
                echo "  ${line}"
            fi
        done || echo "  (no results — check opkg feeds: cat /etc/opkg/*.conf)"
        ;;
esac

echo ""
echo "To install a found package:"
echo "  bash skills/imx95-package/scripts/install_pkg.sh <package-name>"
