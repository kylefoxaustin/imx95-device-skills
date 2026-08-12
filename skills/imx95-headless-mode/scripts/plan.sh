#!/bin/bash
# skills/imx95-headless-mode/scripts/plan.sh
#
# Shows current display configuration: DRM connectors, active display manager,
# framebuffer state. Read-only — makes no changes.
# Also shows what apply.sh would change.
#
# Usage: plan.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0")"
    echo "Shows current display configuration. Read-only."
}
[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage && exit 0

echo "=== DISPLAY CONFIGURATION ==="
echo ""

# ---------------------------------------------------------------------------
# DRM connectors
# ---------------------------------------------------------------------------
echo "--- DRM Connectors ---"
DRM_FOUND=0
if [ -d /sys/class/drm ]; then
    for conn in /sys/class/drm/card*-*/; do
        [ -d "${conn}" ] || continue
        conn_name=$(basename "${conn}")
        # Skip render nodes and plain card entries
        echo "${conn_name}" | grep -q "\-" || continue

        status=$(cat "${conn}status"  2>/dev/null || echo "unknown")
        enabled=$(cat "${conn}enabled" 2>/dev/null || echo "unknown")
        dpms=$(cat "${conn}dpms"     2>/dev/null || echo "unknown")

        # Get current mode if connected
        mode=""
        if [ "${status}" = "connected" ] && [ -f "${conn}modes" ]; then
            mode=$(head -1 "${conn}modes" 2>/dev/null || echo "")
        fi

        printf "  %-30s status=%-14s enabled=%-10s dpms=%s\n" \
            "${conn_name}" "${status}" "${enabled}" "${dpms}"
        [ -n "${mode}" ] && printf "    Current mode: %s\n" "${mode}"
        DRM_FOUND=1
    done
fi
[ "${DRM_FOUND}" = "0" ] && echo "  No DRM connectors found (DRM subsystem not active or no display hardware)"

# ---------------------------------------------------------------------------
# Framebuffer devices
# ---------------------------------------------------------------------------
echo ""
echo "--- Framebuffer Devices ---"
FB_FOUND=0
for fb in /dev/fb*; do
    [ -e "${fb}" ] || continue
    fb_name=$(basename "${fb}")
    fb_sys="/sys/class/graphics/${fb_name}"

    virtual_size=$(cat "${fb_sys}/virtual_size" 2>/dev/null || echo "unknown")
    bits_per_pixel=$(cat "${fb_sys}/bits_per_pixel" 2>/dev/null || echo "unknown")
    blank=$(cat "${fb_sys}/blank" 2>/dev/null || echo "unknown")
    blank_str="active"; [ "${blank}" = "1" ] && blank_str="BLANKED"

    printf "  %-12s  size=%-16s bpp=%-4s  state=%s\n" \
        "${fb}" "${virtual_size}" "${bits_per_pixel}" "${blank_str}"
    FB_FOUND=1
done
[ "${FB_FOUND}" = "0" ] && echo "  No framebuffer devices found"

# ---------------------------------------------------------------------------
# Display manager detection
# ---------------------------------------------------------------------------
echo ""
echo "--- Display Manager ---"
DM_NAME=""
DM_STATE="not running"

# Check common display managers in priority order
for dm in weston gdm3 gdm lightdm sddm xorg; do
    if systemctl is-active --quiet "${dm}" 2>/dev/null; then
        DM_NAME="${dm}"
        DM_STATE="running (active)"
        break
    elif systemctl is-enabled --quiet "${dm}" 2>/dev/null; then
        DM_NAME="${dm}"
        DM_STATE="enabled but not running"
        break
    fi
done

# Also check for weston launched via custom service
if [ -z "${DM_NAME}" ]; then
    for dm_service in /etc/systemd/system/weston*.service \
                      /lib/systemd/system/weston*.service; do
        [ -f "${dm_service}" ] && DM_NAME="weston" && DM_STATE="service file found" && break
    done
fi

if [ -n "${DM_NAME}" ]; then
    printf "  %-20s: %s\n" "Display manager" "${DM_NAME}"
    printf "  %-20s: %s\n" "State"           "${DM_STATE}"
else
    echo "  No display manager detected — board may already be headless"
fi

# ---------------------------------------------------------------------------
# Kernel cmdline display flags
# ---------------------------------------------------------------------------
echo ""
echo "--- Kernel Cmdline (display-related) ---"
CMDLINE=$(cat /proc/cmdline 2>/dev/null || echo "")
DISPLAY_ARGS=$(echo "${CMDLINE}" | tr ' ' '\n' | grep -iE "video=|drm|fb|display|hdmi|dsi|lvds" || true)
if [ -n "${DISPLAY_ARGS}" ]; then
    echo "${DISPLAY_ARGS}" | sed 's/^/  /'
else
    echo "  No display-specific kernel cmdline arguments found"
fi

# ---------------------------------------------------------------------------
# What apply.sh would do
# ---------------------------------------------------------------------------
echo ""
echo "=== WHAT apply.sh WOULD DO ==="
echo ""

if [ -z "${DM_NAME}" ]; then
    echo "  Board appears to already be headless (no display manager running)."
    echo "  apply.sh would:"
    echo "    1. Blank framebuffer: echo 1 > /sys/class/graphics/fb0/blank"
    echo "    2. Report 'already headless'"
else
    echo "  apply.sh would:"
    echo "    1. Stop display manager:    systemctl stop ${DM_NAME}"
    echo "    2. Disable on boot:         systemctl disable ${DM_NAME}"
    echo "    3. Blank framebuffer:       echo 1 > /sys/class/graphics/fb0/blank"
    echo ""
    echo "  To permanently disable DRM at kernel level (requires reboot):"
    echo "    Add to U-Boot bootargs:  video=HDMI-A-1:d video=DSI-1:d"
    echo "    Command: fw_setenv bootargs \"\$(fw_printenv -n bootargs) video=HDMI-A-1:d\""
    echo ""
    echo "  To reverse headless mode:"
    echo "    systemctl enable --now ${DM_NAME}"
fi

echo ""
echo "  Run apply.sh to proceed (requires YES confirmation)."
