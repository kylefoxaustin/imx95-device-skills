# i.MX 95 Sysfs Paths Reference

This document lists all important sysfs and procfs paths on the i.MX 95 (FRDM-IMX95 EVK,
kernel 6.18 on this board; the BSP release line is a different question). Paths are organized by subsystem. Use this as a quick reference when
writing new skills or debugging board issues.

---

## CPU (Cortex-A55 cluster)

```
/sys/devices/system/cpu/cpu{0..5}/
├── online                              # 0=offline, 1=online (not present for cpu0)
├── cpufreq/
│   ├── scaling_cur_freq                # Current frequency in kHz
│   ├── scaling_min_freq                # Minimum allowed frequency in kHz
│   ├── scaling_max_freq                # Maximum allowed frequency in kHz
│   ├── scaling_governor                # Active governor (schedutil, performance, powersave, etc.)
│   ├── scaling_available_governors     # Space-separated list of available governors
│   ├── scaling_available_frequencies   # Space-separated list of OPP frequencies in kHz
│   ├── cpuinfo_cur_freq                # Hardware-reported current frequency (may differ from scaling_cur_freq)
│   ├── cpuinfo_min_freq                # Hardware minimum
│   └── cpuinfo_max_freq                # Hardware maximum (1800000 kHz = 1.8 GHz)
└── topology/
    ├── core_id
    ├── cluster_id
    └── physical_package_id

/proc/cpuinfo                           # Full CPU info including model name, BogoMIPS
/proc/stat                              # Per-CPU time in user/nice/system/idle/iowait/irq/softirq
```

**Notes:**
- All 6 Cortex-A55 cores share a single cpufreq policy (cluster-wide DVFS).
- Setting governor on cpu0 affects all cores.
- Max frequency: 1800 MHz (1800000 kHz).
- Min frequency: 300 MHz (300000 kHz) on most BSP builds.

---

## Thermal

```
/sys/class/thermal/
├── thermal_zone{N}/
│   ├── type                            # Zone name (e.g., "cpu-thermal", "soc-thermal")
│   ├── temp                            # Current temperature in millidegrees Celsius
│   ├── mode                            # "enabled" or "disabled"
│   ├── policy                          # Thermal governor (step_wise, power_allocator)
│   ├── trip_point_{N}_temp             # Trip point temperature in millidegrees
│   ├── trip_point_{N}_type             # "active", "passive", "hot", "critical"
│   └── trip_point_{N}_hyst             # Hysteresis in millidegrees
└── cooling_device{N}/
    ├── type                            # Cooling device type (e.g., "cpufreq", "fan")
    ├── cur_state                       # Current cooling state (0 = no cooling)
    └── max_state                       # Maximum cooling state
```

**Typical zones on FRDM-IMX95 EVK:**

| Zone | Type string | Throttle trip | Critical trip |
|------|-------------|---------------|---------------|
| 0 | cpu-thermal | 85°C | 95°C |
| 1 | soc-thermal | 90°C | 100°C |
| 2 | npu-thermal | 85°C | 95°C |
| 3 | gpu-thermal | 85°C | 95°C |

*Zone numbering may vary by BSP version. Always read `type` file.*

---

## Memory

```
/proc/meminfo                           # Full memory statistics
  MemTotal:       NNNN kB               # Total RAM
  MemFree:        NNNN kB               # Truly free (not including cache)
  MemAvailable:   NNNN kB               # Available for new allocations (includes reclaimable cache)
  Buffers:        NNNN kB               # Kernel buffers
  Cached:         NNNN kB               # Page cache
  SwapTotal:      NNNN kB               # Swap space total
  SwapFree:       NNNN kB               # Swap space free
  CmaTotal:       NNNN kB               # Total CMA reserved
  CmaFree:        NNNN kB               # CMA currently free
  VmallocUsed:    NNNN kB               # vmalloc used
  Shmem:          NNNN kB               # Shared memory (tmpfs)

/sys/kernel/debug/cma/                  # Per-CMA-region stats (requires debugfs)
├── cma-reserved/
│   ├── count                           # Total pages in region
│   └── used                            # Pages currently allocated
└── ...

/sys/kernel/debug/dma_buf/
└── bufinfo                             # DMA-BUF buffer inventory (size, exporter, name)

/proc/{PID}/status
  VmRSS:          NNNN kB               # Resident set size for process PID

/proc/slabinfo                          # Kernel slab allocator statistics
```

**CMA regions — MEASURED on this board** (`references/imx95-ground-truth.md` §2.2–2.3):

| Region | Size | Used by |
|--------|--:|---------|
| `linux,cma` | **960 MiB** | general DMA; the **TFLite Neutron delegate** path draws from here |
| `neutron_memory` (`shared-dma-pool`) | **4 GiB** | dedicated; added by `imx95-19x19-frdm-pro-neutron.dtb` |
| **`CmaTotal`** | **4.94 GiB** | 960 MiB before the DTB swap |

> ⚠️ **An earlier version of this file listed `cma-vpu 256 MB / cma-isp 128 MB / cma-npu 64 MB /
> cma-default 64 MB` as the "typical BSP configuration". Those regions were invented.**
>
> 🔴 `CmaTotal > 4 GiB` means the neutron DTB is booted. **Leave it.** Without it the ONNX Runtime
> Neutron EP cannot initialise — its 2 GiB request fails against the stock 960 MiB pool and the
> graph silently runs on the A55s at a plausible latency.
>
> ✅ A real Neutron offload **drops `CmaFree` (~2 MB)**; a silent CPU fallback does not move it.
> Sample *during* the inference — the buffer is freed at process exit.

---

## GPU (Arm Mali-G310, 1 core r0p0 — graphics only; OpenCL is an ICD stub)

```
/sys/class/devfreq/<gpu-devfreq-node>/
├── cur_freq                            # Current GPU frequency in Hz
├── min_freq                            # Minimum GPU frequency in Hz
├── max_freq                            # Maximum GPU frequency in Hz
├── governor                            # devfreq governor (simple_ondemand, performance, etc.)
├── available_governors                 # Available governors
└── trans_stat                          # Frequency transition statistics

/sys/class/drm/
├── card0/                              # Primary DRM device
│   ├── card0-HDMI-A-1/
│   │   ├── status                      # "connected" or "disconnected"
│   │   ├── enabled                     # "enabled" or "disabled"
│   │   └── modes                       # Supported display modes
│   └── card0-DSI-1/
│       ├── status
│       └── enabled
└── renderD128/                         # DRM render node (OpenCL, Vulkan)

/dev/dri/card0                          # DRM primary node
/dev/dri/renderD128                     # DRM render node
```

**Note:** The GPU devfreq node name varies by BSP. Common names:
- `38000000.gpu` (address-based)
- `gpu` (simple name)
Search: `ls /sys/class/devfreq/`

---

## NPU #1 — eIQ Neutron-S (on-SoC)

> ⚠️ **There is no `ethosu` and no `libvx` on this SoC.** `ethosu` is Arm Ethos-U65 (**i.MX93**);
> `libvx_delegate.so` is VeriSilicon VX (**i.MX8M Plus**). An earlier version of this file listed
> both as "alternative" i.MX95 paths. They are not alternatives — they are different chips.
> See `references/imx95-ground-truth.md` §1.1.

```
/sys/bus/platform/drivers/neutron/           # Neutron platform driver
/sys/bus/platform/drivers/imx-neutron/       # alternative driver name

/dev/neutron0                                # Neutron device node
                                             #  ⚠️ presence != availability

# TFLite delegate stack — TWO files exist on this board [MEASURED]
/usr/lib/libneutron_delegate.so              # 133128 B — confirmed delegating
/usr/lib/liblitert_neutron_delegate.so       # 329736 B — present, UNTESTED

# ONNX Runtime Neutron EP — a SEPARATE stack, separate placement signal
/usr/lib/libonnxruntime.so.1.24.3
/usr/lib/libNeutronDriver.so
```

## NPU #2 — Kinara ARA240 (M.2)

```
PCI 0000:01:00.0  [1e58:0002]  driver uiodma    # lspci -nn | grep 1e58
/usr/share/rt-sdk-ara240_2.1.1/nnapp/nnapp      # runtime CLI
/var/run/proxy.sock                             # proxy_ara240 daemon socket
```

> 🔴 **ARA240 occupancy is host-UNDETECTABLE — measured, not assumed.** The `uiodma` use-count
> reads 0 during a fully busy 500-inference run. Never report this device as free.

---

## Remoteproc (M7 / M33)

```
/sys/bus/remoteproc/devices/
├── remoteproc0/
│   ├── name                            # e.g., "imx-rproc-m7"
│   ├── state                           # "offline", "running", "crashed", "suspended"
│   ├── firmware                        # Firmware filename loaded from /lib/firmware/
│   └── coredump                        # Coredump control
└── remoteproc1/
    ├── name                            # e.g., "imx-rproc-m33"
    ├── state
    └── firmware

/sys/bus/rpmsg/devices/                 # RPMsg channels (IPC between A55 and M7/M33)
```

**States:**
- `offline` — not started (normal if firmware not loaded)
- `running` — firmware loaded and executing
- `crashed` — firmware crashed; check dmesg for details
- `suspended` — in low-power state

---

## DRM / KMS

```
/sys/class/drm/card0-HDMI-A-1/status   # HDMI connector status
/sys/class/drm/card0-DSI-1/status      # MIPI-DSI connector status
/sys/class/drm/card0-DP-1/status       # DisplayPort connector status (if present)

/sys/kernel/debug/dri/0/               # DRM debug info (requires debugfs)
├── state                               # Current KMS state (planes, CRTCs, connectors)
└── clients                             # DRM clients
```

---

## Power Supply / PMIC

```
/sys/class/power_supply/
├── batt/                               # Battery (if present)
│   ├── status                          # "Charging", "Discharging", "Full"
│   ├── capacity                        # Percentage 0–100
│   └── voltage_now                     # Voltage in microvolts
└── usb/                                # USB power input
    └── online                          # 1 if USB power connected

/sys/bus/i2c/devices/                   # PMIC I2C devices
```

---

## Clock Tree

```
/sys/kernel/debug/clk/                  # Clock tree (requires debugfs)
├── clk_summary                         # Full clock tree with rates and enable counts
└── <clock-name>/
    ├── clk_rate                        # Current rate in Hz
    ├── clk_enable_count                # Number of users
    └── clk_prepare_count
```

**Key clocks:**
- `arm_a55_clk` — Cortex-A55 cluster clock
- `gpu_clk` — GPU core clock
- `npu_clk` — NPU clock
- `lcdif_clk` — Display controller clock

---

## U-Boot Environment

```
/sys/firmware/devicetree/base/          # Device tree from U-Boot
├── compatible                          # Board compatible string (NUL-separated)
├── model                               # Board model string
└── chosen/
    └── bootargs                        # Kernel command line from U-Boot

/proc/cmdline                           # Kernel command line (same as bootargs)

# U-Boot env (if fw_printenv is installed):
# fw_printenv                           # Print all U-Boot environment variables
# fw_printenv bootargs                  # Print specific variable
```

---

## Miscellaneous

```
/sys/devices/soc0/
├── soc_id                              # SoC identifier string (e.g., "i.MX95")
├── revision                            # SoC revision (e.g., "1.1")
├── family                              # SoC family (e.g., "Freescale i.MX")
└── machine                             # Machine name

/proc/interrupts                        # Per-CPU interrupt counts
/proc/softirqs                          # Per-CPU softirq counts
/proc/uptime                            # System uptime in seconds
/proc/loadavg                           # Load averages (1/5/15 min)
/proc/version                           # Kernel version string

/sys/bus/usb/devices/                   # USB device tree
/sys/bus/pci/devices/                   # PCIe device list
/sys/bus/i2c/devices/                   # I2C device list
/sys/bus/spi/devices/                   # SPI device list

/sys/class/net/                         # Network interfaces
/sys/class/video4linux/                 # V4L2 video devices
/sys/class/gpio/                        # Legacy GPIO (prefer libgpiod)
/sys/class/leds/                        # LED devices
```
