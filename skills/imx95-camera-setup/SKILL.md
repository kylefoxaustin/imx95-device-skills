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

## 🔴 Camera hardware on this board is [UNKNOWN] — DETECT, DO NOT ASSERT

> **There was a table here listing OV5640 / OV5647 / IMX219 / IMX477 / AR0521 as
> "Common i.MX 95 Camera Sensors", with driver names and max resolutions. It was
> written by an agent that had never seen this board, and NONE of it is confirmed.**
> A companion doc also hardcoded `i2cdetect -y 4` and `-y 5` as CSI0/CSI1. Also unconfirmed.
>
> The table is deleted rather than corrected, because a plausible sensor list is worse than no
> list: an agent that "knows" the sensor is an OV5640 will interpret a blank frame as a pipeline
> bug and spend the session debugging a pipeline for a sensor that is not attached.

**What IS established** (`references/imx95-ground-truth.md` §8): the pipeline shape is
`Sensor (I²C) → MIPI CSI-2 RX → ISI → V4L2` [SOURCED]. That is all.

### What this skill must do instead

1. **Enumerate, never assume:** `v4l2-ctl --list-devices`, then `v4l2-ctl -d <dev> --info` and
   `--list-formats-ext` for each.
2. **Match by DRIVER NAME, never by device number.** `/dev/videoN` numbering is not stable
   across BSP updates or USB-camera insertion — a skill that hardcodes `/dev/video0` will
   silently address the wrong device.
3. **Scan the I²C buses that exist**, rather than assuming which two are CSI:
   `for b in /dev/i2c-*; do i2cdetect -y "${b##*i2c-}"; done`
   *(Known-present expanders, so you can tell them apart from a sensor:* **PCAL6416A** *at
   i2c-2 @0x20 and* **PCAL6524** *at i2c-3 @0x22 [MEASURED].)*
4. **Report what was found and stop.** If nothing is detected, say "no MIPI-CSI sensor detected"
   — do not suggest a probable sensor.

*(Question outstanding with `@imx95-media-test`, who did this board's calibrated model prep and is
the fleet's camera owner. When it is answered, the facts go into `imx95-ground-truth.md` §8 with
tags, and this section gets replaced by measured content.)*

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
