#!/bin/bash
# skills/imx95-headless-mode/scripts/apply.sh
#
# Applies headless mode: stops and disables the display manager,
# blanks the framebuffer. Has a confirm_destructive gate.
#
# Usage: apply.sh [--yes]
#   --yes   Skip interactive confirmation (for scripted use)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--yes]

Disables the display manager and blanks the framebuffer (headless mode).

Options:
  --yes       Skip confirmation prompt (use in scripts)
  -h, --help  Show this help

This is a DESTRUCTIVE operation. It stops the display manager service
and disables it from starting on boot. Running Wayland/X11 applications
will be terminated.
EOF
}

SKIP_CONFIRM=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)     SKIP_CONFIRM=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Show current state first
# ---------------------------------------------------------------------------
log_info "Current display state:"
bash "${SCRIPT_DIR}/plan.sh" 2>/dev/null | grep -E "Display manager|State|DRM|Framebuffer" | \
    sed 's/^/  /' || true

# ---------------------------------------------------------------------------
# Detect display manager
# ---------------------------------------------------------------------------
DM_NAME=""
for dm in weston gdm3 gdm lightdm sddm xorg; do
    if systemctl is-active --quiet "${dm}" 2>/dev/null || \
       systemctl is-enabled --quiet "${dm}" 2>/dev/null; then
        DM_NAME="${dm}"
        break
    fi
done

# ---------------------------------------------------------------------------
# Confirmation gate
# ---------------------------------------------------------------------------
if [ "${SKIP_CONFIRM}" = "0" ]; then
    DESCRIPTION="This will:"
    if [ -n "${DM_NAME}" ]; then
        DESCRIPTION="${DESCRIPTION}
  • Stop display manager '${DM_NAME}' (kills Wayland/X11 sessions)
  • Disable '${DM_NAME}' from starting on boot
  • Blank the framebuffer console"
    else
        DESCRIPTION="${DESCRIPTION}
  • Blank the framebuffer console
  (No display manager detected — board may already be headless)"
    fi
    DESCRIPTION="${DESCRIPTION}

  To reverse: systemctl enable --now ${DM_NAME:-<display-manager>}"

    confirm_destructive "${DESCRIPTION}"
fi

# ---------------------------------------------------------------------------
# Step 1: Stop and disable display manager
# ---------------------------------------------------------------------------
if [ -n "${DM_NAME}" ]; then
    log_info "Stopping display manager: ${DM_NAME}"
    if systemctl is-active --quiet "${DM_NAME}" 2>/dev/null; then
        systemctl stop "${DM_NAME}" && log_info "  Stopped ${DM_NAME}" || \
            log_warn "  Failed to stop ${DM_NAME} — may already be stopped"
    else
        log_info "  ${DM_NAME} is not currently running"
    fi

    log_info "Disabling ${DM_NAME} on boot..."
    systemctl disable "${DM_NAME}" 2>/dev/null && \
        log_info "  Disabled ${DM_NAME}" || \
        log_warn "  Could not disable ${DM_NAME} — check systemctl status"

    # Also mask it to prevent accidental start
    systemctl mask "${DM_NAME}" 2>/dev/null && \
        log_info "  Masked ${DM_NAME} (will not start automatically)" || true
else
    log_info "No display manager to stop — board may already be headless"
fi

# ---------------------------------------------------------------------------
# Step 2: Blank framebuffer
# ---------------------------------------------------------------------------
log_info "Blanking framebuffer..."
FB_BLANKED=0
for fb_sys in /sys/class/graphics/fb*/; do
    [ -d "${fb_sys}" ] || continue
    blank_file="${fb_sys}blank"
    if [ -w "${blank_file}" ]; then
        echo 1 > "${blank_file}" && \
            log_info "  Blanked $(basename "${fb_sys}")" || \
            log_warn "  Could not blank $(basename "${fb_sys}")"
        FB_BLANKED=1
    fi
done
[ "${FB_BLANKED}" = "0" ] && log_info "  No writable framebuffer blank controls found"

# ---------------------------------------------------------------------------
# Step 3: Disable DRM connectors (soft disable, no reboot needed)
# ---------------------------------------------------------------------------
log_info "Disabling DRM connectors..."
DRM_DISABLED=0
for conn in /sys/class/drm/card*-*/; do
    [ -d "${conn}" ] || continue
    conn_name=$(basename "${conn}")
    echo "${conn_name}" | grep -q "\-" || continue

    enabled_file="${conn}enabled"
    if [ -w "${enabled_file}" ]; then
        echo "disabled" > "${enabled_file}" 2>/dev/null && \
            log_info "  Disabled ${conn_name}" || true
        DRM_DISABLED=1
    fi
done
[ "${DRM_DISABLED}" = "0" ] && log_info "  DRM connectors not directly writable (normal — handled by display manager stop)"

# ---------------------------------------------------------------------------
# Step 4: Report new state
# ---------------------------------------------------------------------------
echo ""
log_info "Headless mode applied. New state:"
echo ""

# DRM connectors
for conn in /sys/class/drm/card*-*/; do
    [ -d "${conn}" ] || continue
    conn_name=$(basename "${conn}")
    echo "${conn_name}" | grep -q "\-" || continue
    status=$(cat "${conn}status"  2>/dev/null || echo "unknown")
    enabled=$(cat "${conn}enabled" 2>/dev/null || echo "unknown")
    printf "  %-30s status=%-14s enabled=%s\n" "${conn_name}" "${status}" "${enabled}"
done

echo ""
if [ -n "${DM_NAME}" ]; then
    DM_ACTIVE=$(systemctl is-active "${DM_NAME}" 2>/dev/null || echo "inactive")
    DM_ENABLED=$(systemctl is-enabled "${DM_NAME}" 2>/dev/null || echo "disabled")
    printf "  %-20s: %s (enabled: %s)\n" "${DM_NAME}" "${DM_ACTIVE}" "${DM_ENABLED}"
fi

echo ""
log_info "To restore display mode:"
echo "  systemctl unmask ${DM_NAME:-<display-manager>}"
echo "  systemctl enable --now ${DM_NAME:-<display-manager>}"
echo ""
log_info "To permanently disable DRM at kernel level (survives reboot):"
echo "  Add to U-Boot bootargs: video=HDMI-A-1:d video=DSI-1:d"
echo "  fw_setenv bootargs \"\$(fw_printenv -n bootargs) video=HDMI-A-1:d\""
