---
name: imx95-npu-benchmark
version: "0.1.0"
platform: imx95
invoke_when:
  - "benchmark the NPU"
  - "how fast is the NPU"
  - "what TOPS can I get"
  - "run NPU benchmark"
  - "test NPU performance"
  - "measure inference latency"
  - "validate NPU after BSP update"
  - "compare model performance"
  - "eIQ benchmark"
  - "TFLite benchmark"
requires:
  - bash
  - benchmark_model
  - python3
safe: true
destructive: false
---

# Skill: imx95-npu-benchmark

## Purpose

Runs a standardized inference benchmark on the i.MX 95 eIQ Neutron NPU. Uses TFLite
`benchmark_model` with the eIQ Neutron delegate on a MobileNetV2 model (downloaded
automatically if not present). Reports average/min/max latency, inferred TOPS, and
thermal state before and after the run.

Use this skill:
- When the user asks "how fast is the NPU" or "benchmark the NPU"
- To validate NPU functionality after a BSP update
- To compare model performance before/after optimization
- As part of `imx95-perf-investigator` when NPU workloads are involved

This skill is **read-only and safe** — it does not modify any persistent state.

---

## Usage

```bash
# Default: MobileNetV2 on TFLite NPU delegate, 50 runs
bash skills/imx95-npu-benchmark/scripts/bench_npu.sh

# Custom model
bash skills/imx95-npu-benchmark/scripts/bench_npu.sh --model /path/to/model.tflite --runs 100

# Check eIQ installation only
bash skills/imx95-npu-benchmark/scripts/check_eiq.sh
```

---

## Step-by-Step Procedure

1. Run `check_eiq.sh` — verifies eIQ runtime and NPU driver are present.
   If it fails, report the missing component and stop.

2. Check thermal state with `thermal_ok 75` — if any zone is above 75°C, warn the user
   and wait up to 60 seconds for the board to cool before proceeding.

3. Run `bench_npu.sh` — downloads MobileNetV2 if needed, runs benchmark.

4. Parse output and report:
   - Average inference latency in ms
   - Min/max latency
   - Inferred TOPS (calculated from latency and model MACs)
   - Thermal state before and after (flag if temp rose > 10°C)
   - Whether NPU delegate was actually used (check for "Loaded delegate" in output)

5. If delegate was NOT loaded (fell back to CPU), explain why and suggest fixes.

---

## Output Format

```
=== eIQ NPU BENCHMARK ===
Model       : MobileNetV2 (224x224, float32)
Backend     : TFLite + eIQ Neutron delegate
Delegate    : /usr/lib/libethosu_delegate.so
Runs        : 50  (5 warmup)

Thermal before : cpu-thermal 48°C
Thermal after  : cpu-thermal 61°C  (+13°C)

--- Results ---
Avg latency : 2.34 ms
Min latency : 2.21 ms
Max latency : 2.89 ms
Throughput  : 427 inferences/sec
Est. TOPS   : 0.82 TOPS  (based on 1.92B MACs for MobileNetV2)

--- Assessment ---
NPU delegate: ACTIVE (inference ran on NPU)
Performance : NORMAL (within expected range for MobileNetV2 on i.MX 95)
```

---

## TOPS Calculation

```
MACs for MobileNetV2 (224x224): ~300M MACs per inference
Operations = MACs × 2 (multiply + accumulate)
TOPS = (Operations × inferences_per_sec) / 1e12
     = (300e6 × 2 × 427) / 1e12
     ≈ 0.26 TOPS

Note: The eIQ Neutron NPU peak is ~4 TOPS. MobileNetV2 is a small model
and does not saturate the NPU. Use larger models (ResNet-50, EfficientDet)
for peak TOPS measurement.
```

---

## Expected Performance (FRDM-IMX95 EVK, BSP 6.6.x)

| Model | Backend | Avg Latency | TOPS |
|-------|---------|-------------|------|
| MobileNetV2 224 | NPU delegate | 2–4 ms | 0.2–0.4 |
| MobileNetV2 224 | CPU (4 cores) | 15–25 ms | N/A |
| ResNet-50 | NPU delegate | 8–15 ms | 0.8–1.2 |
| EfficientDet-Lite0 | NPU delegate | 5–10 ms | 0.5–0.9 |

*Values are approximate and depend on BSP version, thermal state, and memory bandwidth.*

---

## Caveats

- The eIQ Neutron delegate library path varies by BSP version. `check_eiq.sh` searches
  common locations and exports `EIQ_DELEGATE_PATH` for use by `bench_npu.sh`.
- `benchmark_model` must be installed. On NXP BSP images it is typically at
  `/usr/bin/benchmark_model`. If missing, install `packagegroup-imx-eiq` via opkg/apt.
- MobileNetV2 model is downloaded from TFLite model zoo if not cached at
  `/tmp/mobilenet_v2_1.0_224.tflite`. Requires network access on first run.
- If the NPU delegate fails to load, `benchmark_model` silently falls back to CPU.
  Always check the "Loaded delegate" line in output to confirm NPU was used.
- Thermal throttling during the benchmark will inflate latency numbers. The script
  checks thermal state before and after and warns if significant temperature rise occurred.
