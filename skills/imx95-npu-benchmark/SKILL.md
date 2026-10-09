---
name: imx95-npu-benchmark
version: "2.0.0"
platform: imx95
accelerator: neutron
invoke_when:
  - "benchmark the NPU"
  - "how fast is the Neutron"
  - "is the NPU actually being used"
  - "run NPU benchmark"
  - "measure inference latency on the NPU"
  - "validate NPU after a BSP update"
  - "why is inference slow"
requires:
  - bash
  - benchmark_model
  - /usr/lib/libneutron_delegate.so
  - /dev/neutron0
safe: true
destructive: false
refuses_rather_than_degrades: true
---

# imx95-npu-benchmark

## Purpose

Benchmark a model on the i.MX95's built-in **eIQ Neutron-S** NPU, and — the part that
matters — **prove the NPU actually executed it**.

This skill exists in its current form because the previous version did not. It searched six
delegate paths, all belonging to other i.MX parts, found none on this board, printed
`"NPU inference will fall back to CPU"`, benchmarked six Cortex-A55 cores, and multiplied
the result into a TOPS figure. Every step of that was working as written.

> ## ⭐ THE ONE RULE: MEASURE **PLACEMENT**, NEVER LATENCY.
>
> The Neutron has three distinct failure modes and **all three return a plausible latency
> with no NPU in it.** Timing cannot tell them apart — it looks fine in every case. The
> delegated-node/partition count is the only honest signal, and it also tells you *which*
> failure you have, which matters because they are fixed in three different places.
>
> | placement | diagnosis | fixed |
> |---|---|---|
> | `1 NeutronGraph / N nodes` | ✅ healthy | — |
> | `1 of N` nodes, rest on CPU | 🔴 converter trap | at CONVERT time |
> | `0 of N` + `Neutron hardware init failed!!!` | 🔴 CMA trap | at RUN time |
> | no placement line at all | 🔴 **cannot prove anything** | before you quote a number |

**The last row is the important one.** Absence of evidence is reported as **failure**, not as
success. A plausible number with no placement line has exactly the shape of all three failures.

> ## 🔴 AND PLACEMENT IS NOT THE WHOLE GATE — IT PROVES EXECUTION, NOT CORRECTNESS.
> This skill's exit 0 means *"the NPU ran this graph."* It does **not** mean the graph computed the
> right answer. The fleet has the worked instance on this very board: a **yolov8l** run with
> **good delegation** and **ZERO detections** — perfect placement, perfect-looking latency, no
> output. A broken run is also a **fast** run, so timing and placement both point the wrong way.
>
> ⇒ **A performance number is not shippable until an output-correctness gate has passed on the same
> artifact.** Exit 0 here plus a silent accuracy failure is exactly the "broken is faster" defect
> this repo exists to stop — one layer past the one it already catches.
>
> ### The gate, and why a cosine is not it
> ```bash
> # host-side, on the captured output tensor vs an fp32 reference
> python3 ~/Documents/GitHub/qualcomm/results/bench_data/tools/yolo_output_gate.py \
>     --out run.npy --ref fp32.npy --json gate.json     # exit 0 = PASS, 2 = VOID
> python3 .../yolo_output_gate.py --self-test           # verified green 2026-09-18
> ```
> ⚠️ **Do not substitute a whole-tensor cosine — it is structurally blind here.** `output0` is
> `[1,84,8400]`: 4 box channels of magnitude ~hundreds plus 80 score channels in `[0,1]`, so dead
> scores move the norm in the 4th decimal. Measured by the fleet: IQ-9075 whole-tensor **0.9997**
> with **0 detections**; Orin **0.9955** with **0 detections**. The gate's own self-test plants the
> zeroed-scores case and reports `whole_cos=1.0, gate=VOID`.
> **This also applies to the Neutron's headline `corr 0.9998` / `cosine 0.99997`** — aggregate
> agreement, not detection correctness (ground truth §2).
> *(Gap found by the 2026-09-17 cold-card drill: nothing in this repo said so before.)*

---

## What this skill refuses to do

These are deliberate, and each one is a defect the previous version shipped.

1. **It will not run without a model you supply.** No default download. The previous version
   fetched a **float32** MobileNetV2 from the TFLite zoo — a model that cannot run on the
   Neutron at all (the delegate path is int8, and the model must additionally be compiled by
   `neutron-converter`). It would have delegated ~nothing and timed the CPU.
2. **It will not report TOPS.** `TOPS = 2 × MACs × IPS` is correct arithmetic and a fabrication
   when the IPS was never proven to be an NPU rate. Neutron peak is **~2–3 TOPS [SOURCED]** and
   it stays labelled.
3. **It will not report any timing unless the placement assertion passed.**
4. **It will not fall back to CPU.** Not being able to use the NPU is a non-zero exit.
5. **It will not bind to `libethosu_delegate.so` or `libvx_delegate.so`.** Those are i.MX93's
   and i.MX8M Plus's. If they are present on the box, the skill says so out loud — their
   presence is what seduced the first implementation.

---

## First measurement — the shortest path that is actually verified

The 2026-09-17 drill's headline finding was that the fleet card had **no path from zero to one
measurement**. This is that path for this skill, and every element below was run on the board.

```bash
# On the board. A neutron-converter-compiled model already exists here [MEASURED 2026-08-12]:
bash skills/imx95-npu-benchmark/scripts/bench_npu.sh --model /root/yolov8n_eiq313.tflite --runs 20
```
**Expect, and treat anything else as a failure:**
```
Placement line: INFO: NeutronDelegate delegate: 1 nodes delegated out of 33 nodes with 1 partitions.
PLACEMENT OK: 1/33 nodes, 1 partition(s).
CmaFree dropped ~8 MB during the run
exit 0
```
**The negative control is on the board too** — `/root/yolov8n_int8_for_neutron.tflite` was never
through the converter. It must give `0 nodes delegated out of 274`, **no** `CmaFree` movement, and
**exit 4**. *If it does not refuse, the gate is broken — run this before trusting any number.*

⚠️ Both are **instance** facts about this physical board's `/root`, not properties of an i.MX95.
⚠️ And per the box above: a passing run here still owes an **output-correctness** check.

## Usage

```bash
# 1. Convert on the HOST with the STANDALONE eIQ Neutron SDK CLI (not pip):
neutron-converter --input model_int8.tflite --target imx95 --output model_neutron.tflite
scp model_neutron.tflite imx95:/run/media/root-mmcblk0p2/

# 2. On the board:
bash skills/imx95-npu-benchmark/scripts/check_eiq.sh          # pre-flight only
bash skills/imx95-npu-benchmark/scripts/bench_npu.sh \
     --model /run/media/root-mmcblk0p2/model_neutron.tflite --runs 50
```

⚠️ **`df -h` before staging a model anywhere.** `/run/media/root-mmcblk0p2` is the default but holds
only **555 M** of 11 G; `/` holds **8.7 G** of 56 G, so "never `/`" is now backwards. Note the two
are **different physical devices** — `/` is the microSD (`mmcblk1`), the default outdir is the eMMC
(`mmcblk0`) — so where you write the log decides which device takes the I/O during a run. And `/` shed
**10 GB in two days** — a free-space figure on this board has a shelf life of hours. Ground-truth §5.

---

## Exit codes — and what Claude should say for each

### `bench_npu.sh`

| code | meaning | what to tell the user |
|---|---|---|
| 0 | healthy | Report the placement counts *and* the latency, with tags. Say it is batch-1 single-stream. |
| 1 | pre-flight failed / no runner | The NPU cannot run here. Do not offer a CPU number as a consolation — that substitution is the original bug. |
| 3 | **CMA trap** | Intermittent, depends on page-cache state. Check `CmaFree` before/after. Remedy (`drop_caches`) is **[UNVERIFIED]** — do not promise it works. |
| 4 | **converter trap / fragmentation** | Deterministic. Either the graph never fused (broken pip converter → re-convert with standalone SDK 3.1.3), or it crossed the NPU/CPU boundary more than once. |
| 5 | no placement evidence | Say plainly: *"the run produced a latency, but nothing proves the NPU executed, so there is no number."* |
| 6 | thermal refusal | Board too hot; a throttled run measures a board state nobody will remember when the number is quoted. |
| **7** | **a FOREIGN delegate ran the graph** | XNNPACK (CPU) or similar claimed the nodes. Re-run with `--use_xnnpack=false`. **This is a CPU run wearing a placement line** — never quote it. |
| 8 | runner crashed | The binary exited non-zero. Placement may have printed; the run still did not complete. |
| **9** | **the two proofs disagree** | Placement says the NPU ran; `CmaFree` never moved. Withhold the number until it is understood — a disagreement between the only two proofs is not a caveat. |

### `check_eiq.sh` — **disjoint codes on purpose**

| code | meaning |
|---|---|
| 0 | ready |
| 10 | not an i.MX95 |
| 11 | delegate missing (or only another SoC's delegate present) |
| 12 | `/dev/neutron0` missing — driver did not bind |
| 13 | no TFLite runner available |

> These do **not** overlap `bench_npu.sh`'s. They used to: `check_eiq.sh` exit 3 meant "driver did
> not bind" while the table above says 3 = CMA trap — so an agent running the pre-flight standalone,
> exactly as this file instructs, would deliver the CMA remediation for a missing driver. **A wrong
> diagnosis produced by two individually-correct documents.**

---

## Interpreting a healthy result

A healthy i.MX95 CNN **fuses the entire conv backbone into ONE NeutronGraph op**. The ~32
remaining nodes are the input-quant / output-dequant / NMS tail running on the A55s.

⚠️ **That tail is normal *for this delegate* — but do not call it harmless.** The dossier's own
e2e bottleneck table names it **"delegate fragmentation"** and identifies it as what *bounds the
deployed number* on this board: the 48 ms in-process infer is **1 graph node on the NPU plus a
32-node tail on the single-threaded A55**, and that infer dominates the frame. An earlier version
of this file called it "not fragmentation" and it was wrong.

Reference points, all [MEASURED] by the fleet (ground-truth §2.5) — quote these rather than
inventing an "expected performance" table:

| model | latency | IPS | delegation |
|---|--:|--:|:--:|
| yolov8n | 32.08 ms | 31.17 | 1 NeutronGraph / 33 |
| yolov8s | 52.3 ms | 19.13 | 1 NeutronGraph / 34 |
| yolov8m | 101.5 ms | 9.85 | 1 NeutronGraph / 34 |
| yolov8l | 182.5 ms | 5.48 | 1 NeutronGraph / 34 |
| yolov8x | 305.8 ms | 3.27 | 1 NeutronGraph / 34 |

- Whole-accelerator **saturated** throughput: **86.25 IPS** (4-worker) [MEASURED] — a
  *different metric* from batch-1. Never rank one against the other.
- Deployable **e2e** pipeline: **18.1 fps** [MEASURED]. ⚠️ **The gap from 31 IPS is INSIDE the
  inference call, not beside it** — the e2e infer is **48 ms** (vs the benchmark's 32 ms), and the
  dossier attributes it to **op coverage**: one node on the NPU, a 32-node tail on the
  single-threaded A55. It is **infer-bound**, not host-pre/post-bound. *(That distinction decides
  the fix: more on-NPU op coverage, not a faster letterbox. The ARA240 is the board's host-bound
  case — see `imx95-ara240` — and mixing the two diagnoses sends you to the wrong lever.)*
- A yolov8n inference costs **0.61 CPU cores (~10%)** [MEASURED] — the offload leaves >90% of
  the host free, which is the actual architectural argument for this NPU.

⚠️ Only yolov8n was tiebroken across 3 specimens. An earlier 36.75 IPS reading was a
cool-board outlier.

---

## Op placement — this is Neutron-**S**, not C

Use `SupportedOperatorsS.md`. `DEPTH_TO_SPACE` is **not** accelerated (falls to the A55 — cheap,
once per frame); `TRANSPOSE_CONV`, `RESIZE_BILINEAR`, `RESIZE_NEAREST_NEIGHBOR` **are**. So a
pixel-shuffle upsample tail lands on the CPU while a transpose-conv tail stays on the NPU — a
real model-design lever.

The driver-3.1.2-vs-converter-3.1.3 microcode mismatch warning is **benign** [MEASURED]: NPU vs
host-CPU output agreed to ±1 int8 LSB, cosine 0.99997.

---

## Caveats

- **`/dev/neutron0` presence is not availability.** It means the driver bound. It says nothing
  about another tenant holding the NPU. Do not build an "is the NPU free?" claim on it.
- **The CMA precondition applies to the TFLite delegate path.** The dedicated 4 GiB
  `neutron_memory` pool (neutron DTB) retires the hazard for the ONNX-EP path only; the delegate
  path still draws from the 960 MiB `linux,cma`.
- **The census is part of the measurement.** `bench_npu.sh` records loadavg and resident
  inference-shaped tenants. A number measured under load is legitimate — pretending the board
  was clean is not.
- **The exact placement wording has not been re-verified verbatim by this repo** across
  `benchmark_model` / `tflite_runtime` / native C. The parser is tolerant about surrounding text
  and strict about the numbers, and reports UNKNOWN rather than success if it cannot find them.
  *(Confirmation requested from the fleet sessions that built the native harness.)*

## References

- `references/imx95-ground-truth.md` §2 — the Neutron section, with provenance tags
- `lib/neutron.sh` — the placement parser and the refusal gate
