---
name: imx95-camera-setup
version: "0.1.0"
platform: imx95
invoke_when:
  - "is my camera detected"
  - "detect MIPI camera"
  - "list cameras"
  - "what cameras are connected"
  - "camera not working"
  - "V4L2 devices"
  - "test camera capture"
  - "capture frames"
  - "check camera pipeline"
  - "ISP camera"
  - "MIPI-CSI"
requires:
  - bash
  - v4l2-ctl
  - grep
  - dmesg
safe: true
destructive: false
---

# Skill: imx95-camera-setup

## Purpose

Detects MIPI-CSI cameras connected to the i.MX 95, lists V4L2 video devices, inspects
the media controller topology, and tests a basic capture pipeline. Reports detected sensor
drivers, supported formats, and any errors in the camera pipeline.

Use this skill:
- When the user asks "is my camera detected?" or "what cameras are connected?"
- When a camera pipeline fails to start
- To verify camera hardware after BSP update or device tree change
- Before starting a GStreamer or OpenCV camera pipeline

This skill is **read-only and safe** — `test_capture.sh` streams frames but does not
save them to disk by default.

---

## Usage

```bash
# Detect all cameras and media topology
bash skills/imx95-camera-setup/scripts/detect_cameras.sh

# Test capture pipeline (30 frames)
bash skills/imx95-camera-setup/scripts/test_capture.sh [/dev/videoN]
```

---

## Step-by-Step Procedure

### Camera detection
1. Run `detect_cameras.sh`.
2. Parse output:
   - List all `/dev/video*` devices with their driver names
   - Note which are capture devices vs output/metadata
   - Report media controller topology if `media-ctl` is available
   - Check dmesg for sensor driver probe messages
3. If no cameras found, check:
   - Is the sensor driver loaded? (`lsmod | grep <sensor>`)
   - Is the device tree correct? (`dmesg | grep -i csi`)
   - Is the MIPI-CSI cable connected?

### Capture test
1. Run `test_capture.sh /dev/videoN` on the detected capture device.
2. Report: frame rate achieved, any dropped frames, any V4L2 errors.
3. If capture fails, report the specific error and suggest fixes.

---

## Output Format

```
=== V4L2 DEVICES ===
/dev/video0   imx-media-capture  [capture]  driver=imx-media
/dev/video1   imx-media-capture  [capture]  driver=imx-media
...

=== MEDIA TOPOLOGY ===
(media-ctl -p output)

=== SENSOR DRIVERS (from dmesg) ===
ov5640 3-003c: ov5640_probe: sensor detected

=== CAPTURE TEST ===
Device    : /dev/video0
Format    : 1920x1080 YUYV
Frame rate: 29.97 fps
Frames    : 30/30 captured, 0 dropped
```

---

## Common i.MX 95 Camera Sensors

| Sensor | Driver | Interface | Max Resolution |
|--------|--------|-----------|----------------|
| OV5640 | ov5640 | MIPI-CSI2 | 2592×1944 |
| OV5647 | ov5647 | MIPI-CSI2 | 2592×1944 |
| IMX219 | imx219 | MIPI-CSI2 | 3280×2464 |
| IMX477 | imx477 | MIPI-CSI2 | 4056×3040 |
| AR0521 | ar0521 | MIPI-CSI2 | 2592×1944 |

---

## Caveats

- `media-ctl` may not be installed on minimal images. Install with:
  `apt-get install v4l-utils` or `opkg install v4l-utils`
- The i.MX 95 ISP pipeline requires specific media controller link configuration
  before capture. `detect_cameras.sh` reports the topology but does not configure links.
- `test_capture.sh` uses `v4l2-ctl --stream-mmap` which requires the pipeline to be
  fully configured. If links are not set up, it will fail with EPIPE.
- On some BSP versions, the capture device is `/dev/video0` for ISP output and
  `/dev/video1`–`/dev/video7` for sub-devices. Always check `v4l2-ctl --list-devices`.
