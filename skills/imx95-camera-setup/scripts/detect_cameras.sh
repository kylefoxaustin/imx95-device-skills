#!/bin/bash
# skills/imx95-camera-setup/scripts/detect_cameras.sh
#
# Detects MIPI-CSI cameras on i.MX 95:
#   - Lists /dev/video* devices with driver and capability info
#   - Runs v4l2-ctl --list-devices for human-readable device list
#   - Checks media-ctl topology if available
#   - Reports sensor driver probe messages from dmesg
#
# Usage: detect_cameras.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    echo "Usage: $(basename "$0") [--verbose]"
    echo "Detects MIPI-CSI cameras and V4L2 devices on i.MX 95."
}

VERBOSE=0
[[ "${1:-}" = "--verbose" ]] && VERBOSE=1
[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage && exit 0

require_tool v4l2-ctl "Install with: apt-get install v4l-utils  OR  opkg install v4l-utils"

# ---------------------------------------------------------------------------
# SECTION: V4L2 device list
# ---------------------------------------------------------------------------
echo "=== V4L2 DEVICES ==="
echo ""

VIDEO_DEVICES=()
for dev in /dev/video*; do
    [ -e "${dev}" ] || continue
    VIDEO_DEVICES+=("${dev}")
done

if [ "${#VIDEO_DEVICES[@]}" -eq 0 ]; then
    echo "No /dev/video* devices found."
    echo "  Possible causes:"
    echo "    - Camera sensor not connected or not detected"
    echo "    - ISP/CSI driver not loaded"
    echo "    - Device tree missing camera node"
    echo ""
    echo "  Check: dmesg | grep -iE 'csi|isp|ov5640|imx219|ar0521'"
else
    printf "%-14s %-30s %-12s %s\n" "Device" "Name" "Type" "Driver"
    printf "%-14s %-30s %-12s %s\n" "------" "----" "----" "------"

    for dev in "${VIDEO_DEVICES[@]}"; do
        # Get device capabilities via v4l2-ctl
        caps=$(v4l2-ctl -d "${dev}" --info 2>/dev/null || echo "")

        dev_name=$(echo "${caps}" | grep "Card type" | cut -d: -f2 | xargs || echo "unknown")
        driver=$(echo "${caps}" | grep "Driver name" | cut -d: -f2 | xargs || echo "unknown")

        # Determine device type from capabilities
        dev_type="unknown"
        if echo "${caps}" | grep -q "VIDEO_CAPTURE"; then
            dev_type="capture"
        elif echo "${caps}" | grep -q "VIDEO_OUTPUT"; then
            dev_type="output"
        elif echo "${caps}" | grep -q "VIDEO_M2M"; then
            dev_type="m2m"
        elif echo "${caps}" | grep -q "META_CAPTURE"; then
            dev_type="meta-cap"
        elif echo "${caps}" | grep -q "META_OUTPUT"; then
            dev_type="meta-out"
        fi

        printf "%-14s %-30s %-12s %s\n" "${dev}" "${dev_name:0:29}" "${dev_type}" "${driver}"

        if [ "${VERBOSE}" = "1" ]; then
            # Show supported formats
            echo "  Supported formats:"
            v4l2-ctl -d "${dev}" --list-formats-ext 2>/dev/null | \
                grep -E "Index|Type|Pixel|Size|Interval" | \
                sed 's/^/    /' | head -20 || echo "    (could not query formats)"
            echo ""
        fi
    done
fi

# ---------------------------------------------------------------------------
# SECTION: v4l2-ctl --list-devices (human-readable)
# ---------------------------------------------------------------------------
echo ""
echo "=== DEVICE LIST (v4l2-ctl) ==="
v4l2-ctl --list-devices 2>/dev/null | sed 's/^/  /' || \
    echo "  (v4l2-ctl --list-devices failed)"

# ---------------------------------------------------------------------------
# SECTION: Media controller topology
# ---------------------------------------------------------------------------
echo ""
echo "=== MEDIA TOPOLOGY ==="

if command -v media-ctl &>/dev/null; then
    MEDIA_DEVICES=()
    for mdev in /dev/media*; do
        [ -e "${mdev}" ] && MEDIA_DEVICES+=("${mdev}")
    done

    if [ "${#MEDIA_DEVICES[@]}" -eq 0 ]; then
        echo "No /dev/media* devices found."
    else
        for mdev in "${MEDIA_DEVICES[@]}"; do
            echo "Media device: ${mdev}"
            media-ctl -d "${mdev}" -p 2>/dev/null | sed 's/^/  /' || \
                echo "  (media-ctl failed for ${mdev})"
            echo ""
        done
    fi
else
    echo "media-ctl not available."
    echo "  Install with: apt-get install v4l-utils  OR  opkg install v4l-utils"
    echo ""
    echo "  Listing /dev/media* devices:"
    for mdev in /dev/media*; do
        [ -e "${mdev}" ] && echo "  ${mdev}" || true
    done
    [ ! -e /dev/media0 ] && echo "  (none found)"
fi

# ---------------------------------------------------------------------------
# SECTION: Sensor drivers from dmesg
# ---------------------------------------------------------------------------
echo ""
echo "=== SENSOR DRIVERS (dmesg) ==="

# Known i.MX 95 / MIPI-CSI sensor driver names
SENSOR_PATTERNS="ov5640|ov5647|ov8865|ov13858|imx219|imx477|imx290|imx327|ar0521|ar0144|mt9m114|gc2145|sc2235"
ISP_PATTERNS="imx-media|imx8-isi|imx-isi|mxc-mipi|csi2rx|dw-mipi-csi|samsung-mipi"

echo "Camera sensor probe messages:"
dmesg --notime 2>/dev/null | \
    grep -iE "(${SENSOR_PATTERNS})" | \
    grep -iE "probe|detect|found|sensor|camera|init" | \
    tail -20 | sed 's/^/  /' || echo "  (none found)"

echo ""
echo "ISP/CSI driver messages:"
dmesg --notime 2>/dev/null | \
    grep -iE "(${ISP_PATTERNS})" | \
    grep -iE "probe|register|init|enable|link" | \
    tail -10 | sed 's/^/  /' || echo "  (none found)"

echo ""
echo "CSI/camera errors (if any):"
dmesg --notime 2>/dev/null | \
    grep -iE "csi|isp|mipi|camera|sensor" | \
    grep -iE "error|fail|timeout|overflow|underflow" | \
    tail -10 | sed 's/^/  /' || echo "  (none found)"

# ---------------------------------------------------------------------------
# SECTION: Loaded camera-related kernel modules
# ---------------------------------------------------------------------------
echo ""
echo "=== CAMERA KERNEL MODULES ==="
lsmod 2>/dev/null | grep -iE "ov5640|ov5647|imx219|imx477|ar0521|imx_media|imx8_isi|mxc_mipi|csi2|v4l2|videobuf" | \
    awk '{printf "  %-30s %s\n", $1, $3}' || echo "  (none found or lsmod unavailable)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== SUMMARY ==="
CAPTURE_COUNT=$(for dev in "${VIDEO_DEVICES[@]:-}"; do
    [ -e "${dev}" ] || continue
    v4l2-ctl -d "${dev}" --info 2>/dev/null | grep -q "VIDEO_CAPTURE" && echo "${dev}"
done | wc -l)

printf "  %-24s: %d\n" "Total V4L2 devices"   "${#VIDEO_DEVICES[@]:-0}"
printf "  %-24s: %d\n" "Capture devices"       "${CAPTURE_COUNT}"

if [ "${CAPTURE_COUNT}" -gt 0 ]; then
    echo ""
    echo "  To test capture, run:"
    echo "    bash skills/imx95-camera-setup/scripts/test_capture.sh /dev/video0"
else
    echo ""
    echo "  No capture devices found. Troubleshooting steps:"
    echo "    1. Check physical MIPI-CSI cable connection"
    echo "    2. Verify sensor power: check device tree 'vdddo-supply', 'vdda-supply'"
    echo "    3. Check sensor I2C: i2cdetect -y <bus>"
    echo "    4. Check dmesg: dmesg | grep -i 'ov5640\|imx219\|csi'"
    echo "    5. Verify device tree has camera node enabled"
fi
