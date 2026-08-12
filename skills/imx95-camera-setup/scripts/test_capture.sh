#!/bin/bash
# skills/imx95-camera-setup/scripts/test_capture.sh
#
# Tests a V4L2 capture pipeline by streaming frames from a video device.
# Uses v4l2-ctl --stream-mmap to capture N frames and reports frame rate
# and any errors. Does NOT save frames to disk by default.
#
# Usage: test_capture.sh [DEVICE] [--frames N] [--format FMT] [--save DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [DEVICE] [OPTIONS]

Arguments:
  DEVICE        V4L2 device to test (default: /dev/video0)

Options:
  --frames N    Number of frames to capture (default: 30)
  --format FMT  Pixel format (e.g., YUYV, NV12, MJPG) — uses device default if not set
  --save DIR    Save captured frames as raw files to DIR (default: no save)
  --list-formats  List supported formats and exit
  -h, --help    Show this help

Examples:
  $(basename "$0")
  $(basename "$0") /dev/video1 --frames 60
  $(basename "$0") /dev/video0 --format NV12 --save /tmp/frames
EOF
}

DEVICE="/dev/video0"
NUM_FRAMES=30
PIXEL_FORMAT=""
SAVE_DIR=""
LIST_FORMATS=0

# Parse positional device arg first
if [[ $# -gt 0 ]] && [[ "$1" != --* ]]; then
    DEVICE="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --frames)       NUM_FRAMES="$2"; shift 2 ;;
        --format)       PIXEL_FORMAT="$2"; shift 2 ;;
        --save)         SAVE_DIR="$2"; shift 2 ;;
        --list-formats) LIST_FORMATS=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

require_tool v4l2-ctl "Install with: apt-get install v4l-utils  OR  opkg install v4l-utils"

# ---------------------------------------------------------------------------
# Validate device
# ---------------------------------------------------------------------------
if [ ! -e "${DEVICE}" ]; then
    log_error "Device ${DEVICE} not found."
    log_error "Available video devices:"
    ls /dev/video* 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    exit 1
fi

# Check it's a capture device
CAPS=$(v4l2-ctl -d "${DEVICE}" --info 2>/dev/null || echo "")
if ! echo "${CAPS}" | grep -q "VIDEO_CAPTURE"; then
    log_error "${DEVICE} does not support VIDEO_CAPTURE."
    log_error "Device capabilities:"
    echo "${CAPS}" | grep -E "Capabilities|Device Caps" | sed 's/^/  /'
    exit 1
fi

# ---------------------------------------------------------------------------
# List formats if requested
# ---------------------------------------------------------------------------
if [ "${LIST_FORMATS}" = "1" ]; then
    echo "Supported formats for ${DEVICE}:"
    v4l2-ctl -d "${DEVICE}" --list-formats-ext 2>/dev/null | sed 's/^/  /' || \
        echo "  (could not query formats)"
    exit 0
fi

# ---------------------------------------------------------------------------
# Get current / set format
# ---------------------------------------------------------------------------
echo "=== CAPTURE TEST ==="
echo ""

# Get current format
CURRENT_FMT=$(v4l2-ctl -d "${DEVICE}" --get-fmt-video 2>/dev/null || echo "")
CUR_WIDTH=$(echo "${CURRENT_FMT}"  | grep -oP 'Width/Height\s*:\s*\K[0-9]+' | head -1 || echo "0")
CUR_HEIGHT=$(echo "${CURRENT_FMT}" | grep -oP 'Width/Height\s*:\s*[0-9]+/\K[0-9]+' | head -1 || echo "0")
CUR_FMT=$(echo "${CURRENT_FMT}"    | grep -oP "Pixel Format\s*:\s*'\K[^']+" | head -1 || echo "unknown")

printf "%-14s: %s\n" "Device"   "${DEVICE}"
printf "%-14s: %s\n" "Driver"   "$(echo "${CAPS}" | grep 'Driver name' | cut -d: -f2 | xargs || echo 'unknown')"
printf "%-14s: %s\n" "Card"     "$(echo "${CAPS}" | grep 'Card type'   | cut -d: -f2 | xargs || echo 'unknown')"

# Set format if requested
if [ -n "${PIXEL_FORMAT}" ]; then
    log_info "Setting pixel format to ${PIXEL_FORMAT}..."
    v4l2-ctl -d "${DEVICE}" --set-fmt-video="pixelformat=${PIXEL_FORMAT}" 2>/dev/null || \
        log_warn "Could not set format ${PIXEL_FORMAT} — using device default"
    # Re-read format
    CURRENT_FMT=$(v4l2-ctl -d "${DEVICE}" --get-fmt-video 2>/dev/null || echo "")
    CUR_FMT=$(echo "${CURRENT_FMT}" | grep -oP "Pixel Format\s*:\s*'\K[^']+" | head -1 || echo "unknown")
fi

printf "%-14s: %dx%d %s\n" "Format" "${CUR_WIDTH}" "${CUR_HEIGHT}" "${CUR_FMT}"
printf "%-14s: %d\n" "Frames"   "${NUM_FRAMES}"

# ---------------------------------------------------------------------------
# Create save directory if needed
# ---------------------------------------------------------------------------
if [ -n "${SAVE_DIR}" ]; then
    mkdir -p "${SAVE_DIR}"
    log_info "Saving frames to: ${SAVE_DIR}"
fi

# ---------------------------------------------------------------------------
# Run capture
# ---------------------------------------------------------------------------
echo ""
log_info "Starting capture (${NUM_FRAMES} frames)..."

START_TIME=$(date +%s%N)

# Build v4l2-ctl command
V4L2_ARGS=(
    "-d" "${DEVICE}"
    "--stream-mmap"
    "--stream-count=${NUM_FRAMES}"
)

if [ -n "${SAVE_DIR}" ]; then
    V4L2_ARGS+=("--stream-to=${SAVE_DIR}/frame-%04d.raw")
fi

# Capture and parse output
CAPTURE_OUTPUT=$(v4l2-ctl "${V4L2_ARGS[@]}" 2>&1) || {
    log_error "Capture failed. Output:"
    echo "${CAPTURE_OUTPUT}" | tail -20
    echo ""
    echo "Common causes:"
    echo "  - Media controller links not configured (run media-ctl to set up pipeline)"
    echo "  - Sensor not streaming (check sensor power and I2C)"
    echo "  - Format mismatch (try --list-formats)"
    echo "  - Buffer allocation failed (check CMA: grep CmaFree /proc/meminfo)"
    exit 1
}

END_TIME=$(date +%s%N)
ELAPSED_MS=$(( (END_TIME - START_TIME) / 1000000 ))
ELAPSED_S=$(awk "BEGIN{printf \"%.2f\", ${ELAPSED_MS}/1000}")

# Parse capture statistics from v4l2-ctl output
FRAMES_CAPTURED=$(echo "${CAPTURE_OUTPUT}" | grep -oP '\d+(?= frames captured)' | tail -1 || echo "${NUM_FRAMES}")
FRAMES_DROPPED=$(echo "${CAPTURE_OUTPUT}"  | grep -oP '\d+(?= frames dropped)'  | tail -1 || echo "0")

# Calculate frame rate
FPS=0
if [ "${ELAPSED_MS}" -gt 0 ]; then
    FPS=$(awk "BEGIN{printf \"%.2f\", ${FRAMES_CAPTURED} * 1000 / ${ELAPSED_MS}}")
fi

# ---------------------------------------------------------------------------
# Report results
# ---------------------------------------------------------------------------
echo ""
echo "--- Results ---"
printf "%-16s: %s / %s\n" "Frames captured" "${FRAMES_CAPTURED}" "${NUM_FRAMES}"
printf "%-16s: %s\n"      "Frames dropped"  "${FRAMES_DROPPED}"
printf "%-16s: %s seconds\n" "Elapsed"       "${ELAPSED_S}"
printf "%-16s: %s fps\n"  "Frame rate"       "${FPS}"

if [ -n "${SAVE_DIR}" ]; then
    SAVED_COUNT=$(ls "${SAVE_DIR}"/frame-*.raw 2>/dev/null | wc -l || echo "0")
    printf "%-16s: %s files in %s\n" "Saved frames" "${SAVED_COUNT}" "${SAVE_DIR}"
fi

echo ""
echo "--- Assessment ---"
if [ "${FRAMES_DROPPED}" = "0" ]; then
    echo "Capture: CLEAN — no dropped frames"
else
    DROPPED_PCT=$(awk "BEGIN{printf \"%.1f\", ${FRAMES_DROPPED} * 100 / ${NUM_FRAMES}}")
    log_warn "Dropped ${FRAMES_DROPPED} frames (${DROPPED_PCT}%)"
    echo "  Possible causes: CPU overload, memory bandwidth saturation, ISP pipeline stall"
fi

# FPS assessment
EXPECTED_FPS=30
FPS_INT=$(echo "${FPS}" | cut -d. -f1)
if [ "${FPS_INT}" -ge $(( EXPECTED_FPS - 2 )) ]; then
    echo "Frame rate: OK (${FPS} fps ≈ ${EXPECTED_FPS} fps target)"
elif [ "${FPS_INT}" -ge $(( EXPECTED_FPS / 2 )) ]; then
    log_warn "Frame rate: LOW (${FPS} fps, expected ~${EXPECTED_FPS} fps)"
    echo "  Check: CPU governor, thermal throttling, ISP pipeline configuration"
else
    log_warn "Frame rate: VERY LOW (${FPS} fps)"
    echo "  Check: media-ctl link configuration, sensor frame rate setting"
    echo "  Run: v4l2-ctl -d ${DEVICE} --get-parm"
fi
