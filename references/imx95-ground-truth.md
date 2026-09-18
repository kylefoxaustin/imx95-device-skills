# i.MX 95 / FRDM-IMX95-PRO — GROUND TRUTH

> **This file is the ONLY place either i.MX 95 skills repo is allowed to get a hardware fact from.**
> If a `SKILL.md` or a script needs a constant — a library path, a device node, a machine name, a
> performance number — it comes from here or it does not get written.
>
> **Why this file exists:** the first version of both repos was written by an agent with **no board
> access**, from plausible inference. It reached for the i.MX93 and i.MX8M Plus answers because those
> are what an i.MX-shaped question retrieves. Every one of those guesses read as confident, correct
> prose. **The defect was never the prose — it was that nothing in the repo could tell a measured fact
> from a plausible one.** This file is that mechanism.

---

## 0. The provenance contract — read before quoting anything below

Every fact carries exactly one tag. **A fact with no tag is a bug in this file, not a fact.**

| tag | meaning | where it may be used |
|---|---|---|
| **[MEASURED]** | run on this physical board, with proof in a fleet artifact | anywhere, including headlines and comparisons |
| **[SOURCED]** | vendor / datasheet / spec — used **only** where on-board measurement is impossible | must stay labelled; **never compared against a [MEASURED] number** |
| **[DERIVED]** | computed from measured numbers | must stay labelled, and it **carries the conditions of BOTH its factors** — a saturated number × a headroom-era factor is a lie at saturation |
| **[UNVERIFIED]** | measured once, not re-confirmed; owes a re-run | must stay labelled; never bare, never in a comparison |
| **[UNKNOWN]** | **nobody in the fleet has established this** | a skill MUST refuse or ask — it may not guess |

> ### ⭐ THE RULE THAT CAUSED THIS REWRITE
> **A [DERIVED] or [SOURCED] number may never be compared against a [MEASURED] one**, and
> **a number that has lost its tag is not a number any more.** Provenance is lost by *copying*, not
> by dishonesty — every hop (measurement → JSON → SKILL.md → a report → a slide) is a place the tag
> falls off, and a bare number looks *more* authoritative than a labelled one, not less.
>
> **Consequence for scripts, and it is not negotiable: a script that cannot establish provenance
> REFUSES. It does not warn and continue.** A warning printed above a number is read as a caveat;
> an exit code is read as a stop. The old `check_eiq.sh` warned *"NPU inference will fall back to
> CPU"* and then benchmarked six A55 cores — the warning was present, correct, and useless.

**Primary source:** `IMX95_BOARD_DOSSIER.md` v2.0 (2026-07-16), author Kyle Fox, at
`~/Documents/GitHub/qualcomm/results/IMX95_BOARD_DOSSIER.md` (`md5 360307ff…`; the copy in
`qualcomm/distribution/` is byte-identical. ⚠️ The copy at
`imx95-isp/qualcomm-imx95-baseline/` **differs** (`md5 b90b646f…`) — treat it as a fork, not a
source, until reconciled).
**Corroborating repos:** `ollama_95_neutron`, `imx95-isp`, `imx95-media-test`, `95emulator`.

---

## 1. Identity — what this board actually is

| fact | value | tag |
|---|---|---|
| Board | **FRDM-IMX95-PRO** | [MEASURED] |
| SoC | NXP **i.MX95**, **rev 2.0** | [MEASURED] |
| DT `compatible` | **`fsl,frdm-imx95-pro fsl,imx95`** | [MEASURED] |
| DT `model` | **`NXP FRDM-IMX95-PRO`** | [MEASURED] |
| CPU | **6× Cortex-A55** (part `0xd05`) — little cores only, **no big cluster** | [MEASURED] |
| CPU clock | 1.8 GHz under load; `ondemand` idles at **1.404 GHz** | [MEASURED] |
| RAM | 16 GB LPDDR | [SOURCED] |
| Memory bandwidth | **~13 GB/s** aggregate (STREAM Triad 6.9 single / 13.2 agg) | [MEASURED] |
| DRAM latency | 143 ns random-chase | [MEASURED] |
| GPU | **Arm Mali-G310**, 1 core, r0p0 — devfreq node `4d900000.gpu` | [MEASURED] |
| GPU compute | **graphics only — OpenCL is an ICD stub** (`libOpenCLDriverStub.so`), no GPGPU path | [MEASURED] |
| Built-in NPU | **eIQ Neutron-S**, `/dev/neutron0` | [MEASURED] |
| Neutron peak | ~2–3 INT8 TOPS (vendor class figure) | [SOURCED] |
| Add-in NPU | **Kinara ARA240** on M.2, PCI `0000:01:00.0` `1e58:0002`, driver `uiodma` | [MEASURED] |
| ARA240 peak | ~40 TOPS | [SOURCED] |
| Real-time cores | **Cortex-M7** (`imx-rproc`, attached/running) + **Cortex-M33** (System Manager) | [MEASURED] |
| Storage | eMMC, 29.6 GB, **298 MB/s read / 152 MB/s write** | read/write [MEASURED], size [SOURCED] |
| OS | Yocto, **Linux 6.18**, **gcc 15.2 on-board** | [MEASURED] |
| Hostname | `imx95evk` | [MEASURED] |
| Process | TSMC 16 nm FinFET (16FFC-class) | [SOURCED] |

### 1.1 ❌ Facts the first version of these repos asserted that are WRONG

**Every one of these is a real i.MX part number — just not this one.** That is precisely why they
survived review: they are not nonsense, they are *the neighbouring SoC's correct answer*.

| the guess | what it actually belongs to | the truth here |
|---|---|---|
| `libethosu_delegate.so` | Arm Ethos-U65 — **i.MX93** | `/usr/lib/libneutron_delegate.so` |
| `libvx_delegate.so` | VeriSilicon/Vivante VX — **i.MX8M Plus** | same as above |
| GPU "Vivante GC7000UL" | **i.MX8M Plus** | Arm **Mali-G310** |
| PMIC "PCA9450 on I²C" | **i.MX8M** family | **PF09**, and **invisible to Linux** (§6) |
| "NPU ~4 TOPS" | — | ~2–3 TOPS [SOURCED] |
| "kernel 6.6.x" | the BSP release line | the board runs **6.18** |
| single NPU | — | **two**, and the second runs a 7B LLM |

> `ollama_95_neutron/docs/ggml-neutron-design-and-build-plan.md:66` warns about the first collision
> **by name**: *"i.MX 93 vs i.MX 95 (don't conflate): i.MX 93 uses Arm Ethos-U65
> (`libethosu_delegate.so`, Vela)… i.MX 95 uses NXP's Neutron-S (`libneutron_delegate.so`,
> closed `neutron-converter`)."* The warning existed before the mistake was made.

---

## 2. The Neutron NPU — and the three ways it lies to you

### 2.0 ⚠️ THERE ARE **TWO** DELEGATE FILES AND **TWO** SOFTWARE STACKS

Corrected 2026-08-12 by `@imx95-isp` and `@ollama_95_neutron`, independently, both [MEASURED].
**This killed the first version of our own fix**, which hardcoded one path and asserted it was *the*
delegate — *"as brittle as the i.MX93 bug you found"*. The property to assert is
**exists-and-loadable**, never **exclusive**.

Present on the board [MEASURED, `ls -la /usr/lib`]:

| file | size | status |
|---|--:|---|
| `/usr/lib/libneutron_delegate.so` | 133128 B | the one confirmed delegating [MEASURED] |
| `/usr/lib/liblitert_neutron_delegate.so` | 329736 B | present, **untested by anyone** — [UNKNOWN] which is go-forward |

**And the delegate is only ONE of two Neutron stacks:**

| stack | loads | placement signal |
|---|---|---|
| **TFLite delegate** (CNN / Path A) | `libneutron_delegate.so` | `NeutronDelegate: N nodes delegated out of M nodes with K partitions` |
| **ONNX Runtime Neutron EP** (LLM / Path B) | `libonnxruntime.so.1.24.3` + `libNeutronDriver.so` | `offloaded_tensors` / `accelerated_nothing`, from per-node EP assignment |

> 🔴 **The two share no placement signal. Never cross-apply them.** A parser that assumes the
> delegate wording appears on the ORT path is broken by construction — the ORT path never loads the
> delegate at all.

**Device node:** `/dev/neutron0` [MEASURED]
**Driver version:** 3.1.2 [MEASURED] · **matched converter SDK: 3.1.3** (benign 1-patch mismatch) [MEASURED]
**Numerical agreement vs int8 CPU:** corr **0.9998** [MEASURED]; an independent native-C harness
measured ±1 int8 LSB / cosine **0.99997** [MEASURED]
**Speed vs the A55 for the same int8 graph:** ~**12×** [MEASURED]

> ### 🔴 PLACEMENT PROVES EXECUTION, NOT CORRECTNESS — the second gate, added 2026-09-17
> A **yolov8l** run on this board had **good delegation and ZERO detections** [card, fleet]. Perfect
> placement, plausible latency, no output. Because a broken run is a *fast* run, neither timing nor
> placement leans the right way. **A number is not shippable until an output-correctness gate passes
> on the same artifact.** This file's placement doctrine below is necessary and **not sufficient**;
> nothing in these repos said so until a cold drill pointed it out.

> ## ⭐⭐ THE ONE RULE: **MEASURE PLACEMENT, NEVER LATENCY.**
> All three failure modes below produce **a plausible latency with no NPU in it**. Timing cannot
> distinguish them — it looks fine in every case. **The partition/node count is the only honest
> signal**, and it tells you *which* failure you have:
>
> | what you see | diagnosis | when it's fixed |
> |---|---|---|
> | `1 NeutronGraph / N nodes` (whole backbone fused) | ✅ **healthy** | — |
> | `1 of N nodes` delegated, rest on CPU | 🔴 **CONVERTER TRAP** (§2.1) — deterministic | at CONVERT time |
> | `0 of N` + `Neutron hardware init failed!!!` | 🔴 **CMA TRAP** (§2.2) — intermittent | at RUN time |
> | delegate never loaded at all | 🔴 **wrong/missing delegate path** | before you run |

### 2.1 🔴 The converter trap — cost a full session

The pip `neutron_converter_SDK_*` packages **are broken for this board**: they stamp microcode
`0.0.0` and delegation collapses — yolov8m goes to **1 of 310 nodes** on the NPU, the rest on the
A55s, ~2079 ms of mostly-CPU [UNVERIFIED]. **Use the standalone eIQ Neutron SDK CLI**, version-matched
to the driver:

```
neutron-converter --input model_int8.tflite --target imx95 --output model_neutron.tflite
```
Kyle's copy: `~/Documents/tools/nxp/eIQ/eiq-neutron-sdk-linux-3.1.3/bin/neutron-converter` [MEASURED]
Skip the 5.8 GB eIQ Toolkit — the standalone SDK is the tool.

### 2.2 🔴 The CMA trap — fails SOFT, which is the whole problem

The ONNX EP requests a flat **2 GiB contiguous** CMA buffer at init. Against the stock 960 MiB pool
that is ENOMEM, and the EP logs — **verbatim, [MEASURED] by `@ollama_95_neutron` via an LD_PRELOAD
ioctl shim** —

```
Neutron hardware init failed!!! All nodes will be assigned to CPU
```

— **at a severity nobody reads**, then silently runs the whole graph on the A55s at a plausible
latency. **You will benchmark the CPU and call it an NPU number.**

> ## 🔴 DO NOT GATE ON THAT STRING. It is an advisory, never the test.
> Both silicon owners said this independently, and the reason is sharper than "logs are unreliable":
>
> **Once the board boots the neutron DTB (§2.3), the string DISAPPEARS.** A skill keyed on it
> therefore **silently PASSES on the very board where the trap is fixed** — and misses every
> other-cause silent fallback besides. *It is a detector that reports green because the environment
> improved.*
>
> ### ✅ The correct assertion — two independent proofs, neither of which depends on log wording:
> 1. **Placement census** — delegated == expected, and **not 0**.
> 2. **`CmaFree` DROPS while the inference runs.** A real offload drops it (~2 MB on a native C
>    harness, **8 MB measured for yolov8n under `benchmark_model`**); **a silent fallback does not
>    move it at all** [MEASURED — `@imx95-isp`, and confirmed on a second stack by this repo].
>
> Point 2 is the one that is easy to miss: `CmaFree` is not only a *hazard* to screen for, it is
> **positive evidence that the NPU executed**, and it depends on no log wording whatsoever.
>
> ### ⚠️ Sample while the interpreter context is ALIVE — the trap is the process lifetime
>
> This is not a "before/after vs during" style preference; getting it wrong **silently disables the
> check in the safe-looking direction**:
>
> | harness | what is alive when you sample | verdict |
> |---|---|---|
> | **persistent** (native C loop) | delegate + buffer held across the timed region | before/after *within the lifetime* works |
> | **one-shot** (`benchmark_model`) | allocates at init, **frees at exit** | a snapshot *around the process* reads "no drop" **on a perfectly healthy run** |
>
> ⇒ **Rule: sample continuously while the interpreter/EP context is alive and keep the MINIMUM.**
> The persistent-harness before/after is a *special case* of that rule, not an alternative to it.
> *(Mechanism supplied by `@imx95-isp` after this repo hit the one-shot case.)*

> ### 🔴 `CmaFree` IS THE SUM OF TWO POOLS, AND THERE IS NO PER-POOL ACCOUNTING
> Found by the 2026-09-17 card drill (TRAP-5), verified on the board:
>
> | pool | size | |
> |---|--:|---|
> | `linux,cma` | **960 MiB** | `linux,cma-default` — **what the TFLite delegate path draws from** |
> | `neutron_memory@100000000` | **4096 MiB** | dedicated, added by the neutron DTB |
> | **`CmaTotal`** | **5056 MiB** | = 960 + 4096 exactly [MEASURED] |
>
> **`/sys/kernel/debug/cma/` does not exist** — `CONFIG_CMA_DEBUGFS` is off. Verified that debugfs
> *is* mounted (68 entries) before concluding absence, since an unmounted debugfs would have
> produced the same empty result.
>
> ⇒ **The old advice "check CmaFree (pool is 960 MiB)" is now misleading.** `linux,cma` can be
> exhausted while `CmaFree` still reads ~4 GB from the *other* pool — so this check **cannot screen
> for the TFLite-delegate CMA trap** on the current DTB. It is a coarse sanity check, nothing more.
>
> **What this does to Gate 2 (`CmaFree` drop as proof of execution):** a drop still shows **some**
> CMA allocation happened during the run, and a silent CPU fallback allocates none — so the gate
> survives. But it **cannot attribute the drop to a pool**, and it is only sound if the census shows
> nothing else allocating CMA concurrently. Quote it as *"an allocation occurred"*, never as
> *"`linux,cma` is healthy"*.

- Check `grep -i CmaFree /proc/meminfo` **before AND after** every run — for both reasons.
- Observed under self-inflicted page-cache pressure (a 4.4 GB scp + a 6-way build).
- ⚠️ **Remedy status:** cause CONFIRMED, remedy (`drop_caches`) **NOT confirmed** — do not promise it
  works until someone posts the clean re-run. [UNVERIFIED]
- **A plain INT8 tflite that never went through `neutron-converter` gives `0 nodes delegated out of
  23`** [MEASURED, `@imx95-isp`] / **`0 out of 274`** for yolov8n [MEASURED, this repo] — so "the
  converter step is mandatory" is *detectable*, not merely documented. `neutron-converter` is **not
  on the board** (`which` → absent) [MEASURED].
  > ### ⭐ **THE CONVERTER FUSES — ABSENCE OF FUSION IS THE DISCRIMINATOR.**
  > `0 delegated` **alone is not the tell**, because a *healthy* fused run also shows only **1**
  > delegated node. The signal is `0 delegated` **AND an unfused node TOTAL** (274 here, 23 there,
  > 310 in the documented trap) against a fused graph's 33–34. This is why the gate keys on the
  > **total**, not on the delegated count. *(Framing from `@imx95-isp`.)*

### 2.3 ⚙️ The board boots the neutron DTB — LEAVE IT

Boot DTB was swapped to **`imx95-19x19-frdm-pro-neutron.dtb`**, adding a dedicated **4 GiB
`neutron_memory` `shared-dma-pool`** (CmaTotal 960 MiB → **4.94 GiB**) [MEASURED].

- **Without it the ONNX-Runtime GenAI EP cannot init at all** — its 2 GiB `BUFFER_CREATE` fails
  against the stock 960 MiB pool → silent all-CPU fallback. *That single failure is why the Neutron
  was believed "CNN-only" for months.*
- Strict improvement: `linux,cma` still 960 MiB, `membomb` re-measured **16.0 GB/s identical**
  before/after [MEASURED]. Vision/CNN work unaffected.
- Live DTB: `/run/media/boot-mmcblk1p1/imx95-19x19-frdm-pro.dtb`; originals backed up as `.ORIG`
  there and in `/root`. Revert: `cp /root/*.ORIG <boot path> && sync && reboot`.
- ⚠️ **A "restore to stock DTB" cleanup would SILENTLY break the board** into the CNN-only-looking
  state. Never do it as a reaper action.

### 2.4 Neutron-**S** op placement — it is S, not C

Use `SupportedOperatorsS.md`, **not** the "C" document [MEASURED]:
- **NOT accelerated:** `DEPTH_TO_SPACE` (falls to A55 — cheap, once/frame)
- **Accelerated:** `TRANSPOSE_CONV`, `RESIZE_BILINEAR`, `RESIZE_NEAREST_NEIGHBOR`

> ### ✅ **`DEPTH_TO_SPACE` IS THE ONLY OP ALLOWED TO FALL TO THE A55.**
> [MEASURED, `@imx95-isp`] **Anything else appearing in the fallback set is a topology regression,
> not a tuning knob.** This is worth stating as a rule because it converts a vague instruction
> ("inspect the placement and use your judgement") into a **decidable check** — and a decidable
> check is the only kind a skill can enforce. A DEPTH_TO_SPACE/pixel-shuffle upsample tail is fine;
> a transpose-conv tail would have stayed on the NPU, so seeing one on the CPU means something moved
> that should not have.
- ONNX-EP path: `MatMulNBits` (int4) and `MatMulInteger` (int8) → Neutron;
  **`bmm` (var×var, attention QK^T) and `Softmax` → REJECTED, stay on CPU**; `MatMul` fp32 → rejected.

### 2.5 Measured CNN performance — quote these, never invent a table

YOLOv8 INT8, batch-1 single-stream, TFLite Neutron delegate, converted with matched SDK v3.1.3.
**Every model fuses the entire conv backbone into ONE NeutronGraph op.**

| model | latency | IPS | delegation | tag |
|---|--:|--:|:--:|:--|
| yolov8n | 32.08 ms | **31.17** | 1 NeutronGraph / 33 | [MEASURED] (3-specimen tiebreaker) |
| yolov8s | 52.3 ms | **19.13** | 1 NeutronGraph / 34 | [MEASURED] |
| yolov8m | 101.5 ms | **9.85** | 1 NeutronGraph / 34 | [MEASURED] |
| yolov8l | 182.5 ms | **5.48** | 1 NeutronGraph / 34 | [MEASURED] |
| yolov8x | 305.8 ms | **3.27** | 1 NeutronGraph / 34 | [MEASURED] |

- **Whole-accelerator saturated throughput: 86.25 IPS** (4-worker) [MEASURED]
- **Deployable e2e pipeline: 18.1 fps** (host letterbox + NMS + infer) [MEASURED]
- CPU cost of a yolov8n inference: **0.61 cores (~10% of the machine)** [MEASURED] — the offload
  leaves >90% of the 6×A55 host free, which is the actual architectural point.
- ⚠️ **Only yolov8n was tiebroken.** An earlier 36.75 IPS reading was a cool-board outlier; 31.17 is
  canonical. s/m/l/x reproduce to ~1% on re-measure.

> ### ⚠️ A FLEET GATE CURRENTLY SAYS YOLOv8 IS UNPLACEABLE ON THIS NPU. On silicon, it is not.
> `@95emulator` measured, on an **emulated** QEMU Neutron with a vendor runner, that the
> `NeutronAdd` kernel is **absent** — which takes out every residual architecture *and all of
> YOLOv8*. That result is real and they scoped it correctly (*"strong as a statement about the
> TOOLCHAIN, weak as a statement about the part"*). It has since been adopted as an engine gate
> (`NeutronAdd → unplaceable`) carrying a `toolchain-not-silicon` scope key.
>
> **The rows above are the silicon answer for the matched toolchain** (standalone eIQ SDK 3.1.3 +
> on-board delegate 3.1.2): all five YOLOv8 sizes place and fuse to **1 NeutronGraph**. Same part,
> same op, **opposite verdicts — because the toolchain path differs.**
>
> ⇒ **Never quote an emulated placement verdict as a property of this board**, and if you meet a
> lookup that cannot name the toolchain it is answering for, treat its answer as **unknown**, not
> as "unplaceable". A silicon row outranks an emulated row for the same `(part, op)` — it is never
> averaged with one. *(Raised with `@pai-sizer` and `@docs` 2026-09-17.)*

> **❌ DELETED, DO NOT RESTORE:** the original repo's *"Expected NPU performance"* table
> (MobileNetV2 ~2–4 ms / ~1.5–2.5 TOPS, ResNet-50 ~8–15 ms / ~2.5–3.5 TOPS, YOLOv5s …). Those
> numbers were **invented**. So was its TOPS formula applied to an un-verified latency. **A skill
> that reports TOPS derived from a latency it did not prove ran on the NPU is a fabrication
> machine.** If you want a TOPS figure, it is [SOURCED] ~2–3 and it stays labelled.

---

## 3. The ARA240 (Kinara M.2) — the second NPU, absent from the first version entirely

**Runtime:** `/usr/share/rt-sdk-ara240_2.1.1/` [MEASURED] · **CLI:** `nnapp` · **models:** `.dvm`
**Daemon:** `proxy_ara240` (comm `kinara_main`) owns the hardware and **mmaps the PCI BAR at idle
AND during inference** [MEASURED]. Clients talk to it over `/var/run/proxy.sock`.
**Generative stack:** `optimum-ara` (LLaMA / Qwen / LLaVA VLM / Whisper).
Qwen2.5-7B staged at `/usr/share/llm/Qwen2.5-7B-Instruct/model.dvm` [MEASURED].

| workload | result | tag |
|---|--:|:--|
| yolov8n | **296–298 IPS** hardware (9.5× the Neutron) | [MEASURED] |
| yolov8s / m / l / x | 142 / 54 / 26 / 16 IPS | [MEASURED] |
| yolov8n **deployed e2e** | **23.4 fps** — host-bound, not PCIe-bound | [MEASURED] |
| Qwen2.5-7B decode | **6.3 tok/s** on-accelerator | [MEASURED] |
| Qwen2.5-7B end-to-end | **5.36 tok/s** (short prompt) | [MEASURED] |
| NXP's decode spec | 6.51 tok/s — corroborated within 3% | [SOURCED] |

### 3.2 The e2e decomposition — the numbers a skill is allowed to quote

Raw IPS is 9.5× the Neutron; *deployed single-frame* it collapses to **1.3×**. The 42.8 ms frame,
all [MEASURED]:

| component | cost | share |
|---|--:|--:|
| A55 host — Python int8-quant | ~12 ms | |
| A55 host — ultralytics head-rebuild | ~9.2 ms | |
| A55 host — letterbox + NMS | remainder | **~71% total** |
| ARA240 hardware + PCIe DMA | 3.36 + 1.97 + 1.17 = ~6.5 ms | **~15%** |
| synchronous single-frame dispatch stall | ~4 ms | **~10%** |

- **The bottleneck is the entry-tier A55 host, NOT PCIe bandwidth.** The DMA moves **~739 KB in
  ~2 ms (~600 MB/s)** — far below the PCIe ceiling. It is **latency/setup-bound**.
- Even a **zero-latency** accelerator would land at only **~31 fps**, floored by the host.
- Pipelining the DMA (async/double-buffered) recovers to **≈96.5 fps**.
- **Batch amortisation** (yolov8n): HW IPS is invariant at ~298 (the systolic array is
  batch-insensitive, hw_mean locked at 3.34 ms); *App* IPS scales 91 → 148 → 200 → 237 → **248** at
  batch 1/2/4/8/10 — **2.72×**, reaching 83% of the HW ceiling, with diminishing returns and a real
  latency cost (per-frame **10 ms → 40 ms**).
- ⇒ **A single live camera cannot batch for free — it must buffer, which is latency.** The natural
  batch source is **multi-camera / surround-view**: N sensors produce a genuine batch of N per tick
  with no added latency.

⚠️ **`nnapp` config schema:** only `path:` and an **empty `input_path:`** (the random-input trick)
are [MEASURED]. The rest of the YAML a skill emits — `ep_list:` and friends — is **[UNVERIFIED]**.
It fails safe (nnapp errors out), but say so rather than implying the schema is established.

### 3.1 🔴 ARA240 occupancy is **HOST-UNDETECTABLE** — measured, not assumed

An owner audit across **500 confirmed inferences** found the `uiodma` lsmod use-count stayed **0 the
entire time** — the persistent daemon holds the BAR whether busy or idle. No host-side signal
(`uiodma` refcount, `:5000` ESTAB, BAR-`fuser`) distinguished idle from busy.

> **⇒ A check that reports "✅ ARA240 free" is reporting on a fully-busy board.** The honest
> behaviour is to **refuse to claim** — print *"ARA240 occupancy CANNOT BE DETERMINED FROM THE HOST
> — measured, not assumed"* and treat the resource as **opaque**. This is why the board's asset card
> is `class: opaque`: a dead owner means QUARANTINE, never auto-reap.

**Running a `.dvm` with random inputs** (no preprocessed `.dat` needed): point an `nnapp` config's
model `path:` at the `.dvm` and leave `input_path:` **empty** [MEASURED].

---

## 4. LLM on the Neutron (ONNX-EP "Path B") — real, and full of loaded guns

Prefill **8.43× @L=512** [MEASURED], **decode is a wash — do not offload** (Neutron 8.77 vs A55
8.09 GB/s = 1.08×) [MEASURED]. The win **decays with context**: 9.14× @256 · 8.43× @512 · 5.85× @2048 ·
**2.15× @16384** — attention (`bmm`+`Softmax`) is rejected on silicon, stays on CPU, and scales L².

**A skill must not offer this path without carrying all four of these:**

1. **Q4_0 ONLY.** Q8_0 was whitelisted *by reasoning* and never tested — the EP **claims the node**
   then returns **rel-L2 103%, cosine −0.0019** (orthogonal to the truth) [MEASURED].
2. **Split-K is mandatory.** `MatMulNBits` at K=18944 returns garbage — cosine ≈ 0, values 10⁴–10⁶×
   too large — **non-monotonic in K**, so *no inequality is safe*. Split into validated K=3584 chunks.
3. **Correctness is a JOINT (M,K,N) property.** Per-axis whitelists **certify garbage**: `M=112`
   and `K=3072` are each individually "safe" and the **pair is 7.87% wrong** [MEASURED]. The only
   valid gate is **per-exact-triple on-device validation, cached** — with the cache keyed on a
   **content fingerprint of the weights, re-checked on every hit** (a shape key cannot tell two
   models apart; after a model reload the NPU computes the *previous* model's weights and every
   check reports green), and **adaptive N** (probe 3, escalate to 11 if the engine moved).
4. **Offload quality is per-model and some models do not qualify at all:** Mistral-7B +7.3% → +0.96%
   after protecting block 1; Qwen2.5-7B +12.8% → +1.79% (block 3); **Phi-3-mini +22.4% → +8.14%:
   DO NOT OFFLOAD** [MEASURED]. There is no universal layer index. **A wrong config benchmarks
   identically — the speedup is unchanged, only the model is worse, and there is no symptom.**

**Also:** the Neutron is **NON-DETERMINISTIC at some (M,K,N)** — scatter 0.0000% to ~5.82% across
shapes [MEASURED]. Consequence a customer must be told: **an LLM on Neutron gives different output for
the same prompt even at temperature 0**, which breaks prompt caching, golden-output CI, and any
"deterministic inference" claim. (The Zhouyi X2, Hexagon HMX and NVDLA are all bit-exact.)

---

## 5. Host-side and access facts

| fact | value | tag |
|---|---|---|
| Access | `ssh imx95` (alias on skippy, key auth, user **root, no password**) | [MEASURED] |
| ⚠️ Rootfs | **`/` IS 100% FULL (~300 MB free)** | [MEASURED] |
| Stage large files on | `/run/media/root-mmcblk0p2` — ⚠️ **now 95% full, 555 MB free** (was ~4 G) | [MEASURED 2026-08-12] |
| TFLite C API | `/usr/lib/libtensorflow-lite.so.2.19.0` **exports the full C API** | [MEASURED] |
| …but | **no headers ship**, and there is **no unversioned `.so` symlink** | [MEASURED] |
| Link line | `-l:libtensorflow-lite.so.2.19.0 -lm -lpthread -ldl -lstdc++` | [MEASURED] |
| Package feeds | sealed Yocto — assume **no working feed**; build on host, `scp` over | [MEASURED] |

> ⚠️ **The rootfs fact breaks the original install instructions.** `git clone … /opt/imx95-device-skills`
> on a filesystem with 300 MB free is a coin flip. Install to `/run/media/root-mmcblk0p2` instead.

---

## 6. Power, clocks and the System Manager — RESOLVED 2026-09-12: two resources, two answers

| fact | value | tag |
|---|---|---|
| PMIC | **NXP PF09** | [SOURCED] |
| PMIC visibility to Linux | **NOT VISIBLE** — no PMIC regulator driver in the DT | [MEASURED] |
| SCMI protocols exposed | `0x11` power-domain · `0x12` system · `0x13` perf · `0x14` **clock** · `0x15` sensor · `0x19` pinctrl · NXP vendor `0x80 0x81 0x82 0x84` | [MEASURED ×2] |
| SCMI **voltage** protocol (`0x17`) | **NOT exposed** | [MEASURED ×2] |
| Clocks | DT-expressed; **24 SCMI (SM decides) + 2 local `vpu-csr` (direct)** — see §6.1 | [MEASURED ×2] |
| Board regulators | **19 plain Linux `regulator-fixed` supplies (0 GPIO), no SM in the path** — see §6.2 | [MEASURED ×2] |
| I/O expanders | **PCAL6416A** (i2c-2 @0x20, 16-bit) + **PCAL6524** (i2c-3 @0x22, 24-bit) | [MEASURED] |
| Native GPIO domain | **1.8 V** (`+V1.8_SW`); board I/O **3.3 V** (`+V3.3_SW`) | [MEASURED] |
| Ethernet MAC | **NXP in-house ENETC/NETC** (×3) — **NOT Synopsys DWMAC** | [MEASURED] |
| Ethernet PHY | Motorcomm YT8521 | [MEASURED] |
| VPU | Chips&Media WAVE6 | [SOURCED] |
| USB3 | Cadence USBSS · USB2 ChipIdea · PCIe + I3C: Synopsys DesignWare | [SOURCED] |
| Safety | M7 running · **HW watchdog enabled** · **ELE EdgeLock Enclave** · EDAC bound · ARM RAS · TMU zones | [MEASURED] |

**`[MEASURED ×2]`** = measured on the live board by `@95emulator` (2026-09-12 17:57) **and
independently reproduced by this repo** minutes later with a different instrument (Python `os.walk`
over `/sys/firmware/devicetree/base` + phandle decoding, rather than `find`), under a hard lock,
read-only. Where the two instruments disagree, both numbers are given below.

> ### ⚠️ This section previously said "Who owns power: the M33 System Manager over SCMI" and marked
> the whole question [UNKNOWN] with a mandate to refuse. **That framing was too coarse, and it would
> have made both skills wrong in opposite directions.** "Power" was two different resources with two
> different owners:
> - **clocks** are genuinely SM-owned — but DT is *still the lever*, routed through SCMI;
> - **board regulators** are *not* SM-owned at all — ordinary Linux supplies.
>
> A refuse-everything skill would have blocked a legitimate regulator overlay; a "SM owns it, so
> just poke the DT" skill would have promised clock rates the SM can deny. `@95emulator` also
> corrected their own 08-19 premise, which this file had cited: *"M33 SM-only-SCMI" is right about
> who OWNS the resource — do not read it as "DT has no authority."*

### 6.1 Clocks — express in DT, SCMI carries it, the SM decides

- **The shipped DT uses clock-assignment properties heavily:** `assigned-clocks` **26** nodes,
  `assigned-clock-rates` **23**, `assigned-clock-parents` **26** — identical count from both
  instruments. Consumers include `pcie@4c300000`, `pcie@4c380000`, two `pcie-ep`, `can@443a0000`,
  `sai@443b0000`, `micfil@44520000`, the three `mmc`, `syscon@4b010000`, `system-controller@4cde0000`.
- **They reference the SCMI clock protocol, not a CCM.** `/firmware/scmi/protocol@14` has phandle
  **`0x11`**; the first consumer's blob decodes to `<&scmi_clk 0x23>, <&scmi_clk 0x24>`.
- **Not every clock is SCMI — three provider classes, identified 2026-09-12** (`@95emulator`,
  reproduced by this repo with a parser that resolves each provider's `#clock-cells`):

  | provider | compatible | consumers | authority | read-back mismatch means |
  |---|---|--:|---|---|
  | `scmi_clk` — `/firmware/scmi/protocol@14`, ph `0x11` | — | **24** | request; **SM decides** | **SM denial** |
  | `clock-controller@4c410000`, ph `0x89` | `nxp,imx95-vpu-csr syscon` | **2** — `jpegdec@4c500000` (id `0x2`), `jpegenc@4c550000` (id `0x1`) | **direct**, local syscon — no SM | **a real bug** |
  | anything else | — | 0 today | unknown | refuse |

  > ⚠️ **"They reference the SCMI clock protocol" was true of 24/26, not "they."** A two-way
  > SCMI/not-SCMI test leaves the JPEG clocks with no semantics — and the natural default
  > ("mismatch = the SM said no") would explain away a real bug on a clock the SM never touches.

> ### ✅ The honest contract for a clock skill is **SET AND READ BACK**, never "set".
> A DT overlay **expresses** the request; SCMI **carries** it; the **SM decides** — and it can deny
> per its per-logical-machine permissions. So a skill **generates** the overlay (it is a legitimate
> lever — refusing would be wrong), but it **must not promise the rate will stick**. After boot,
> read the effective rate back (`/sys/kernel/debug/clk/clk_summary` or the consumer driver) and
> report *requested vs effective*. A skill that says "this sets the clock to X" is making a claim
> only the SM can make.

### 6.2 Board regulators — ordinary Linux DT authority

- **SCMI voltage-domain protocol `0x17` is NOT exposed** (checked explicitly by both).
- The board rails are **plain `regulator-fixed` / `regulator-gpio` supplies**: `+V1.8_SW`,
  `+V3.3_SW`, `+V5.0_SW`, `USB_VBUS`, `VDD_SD2_3V3`, `M.2-power-ekey`, `M.2-power-mkey-1/-2`,
  `WLAN_EN`, `DCDC_3V3`, `DCDC_5V`, `EXP_1V8/3V3/5V`, `VCCEXT_12V`, `vref_1v8`, `can1-stby`,
  `can3-stby`, `reg_dummy` (a real `regulator-fixed` node despite the name).
- **Count: 19 DT-backed regulators — reconciled 2026-09-12.** `/sys/class/regulator` shows **20**;
  the extra is **`regulator-dummy`** (driver `reg-dummy`, **no `of_node`**) — the Linux regulator
  framework's built-in dummy, not a board supply. `@95emulator`'s original 20 counted it; both
  sides now agree on 19 [MEASURED ×2].
  - **All 19 are `regulator-fixed`. There are ZERO `regulator-gpio` on this board** — if a count
    ever includes one, the DT changed.
  - ⚠️ **One of the 19 is itself *named* `reg_dummy`** (`regulator-fixed`, has an `of_node`) — a real
    DT node that merely looks like the framework dummy. **Filter on `of_node`, never on the name.**

> ⇒ **Regulator nodes in a DT overlay have ordinary authority with no SM in the path.** A regulator
> skill is legitimate. What v1 got wrong was **the part and the target**, not the mechanism: it
> described PCA9450 PMIC regulators, which do not exist here — the PMIC (PF09) is invisible to
> Linux. The real regulators are **board-level fixed/GPIO supplies**, and those are what an overlay
> edits.

### 6.3 🔧 Method gotcha — `find` does not traverse `/proc/device-tree` on this rootfs

```
find /proc/device-tree -name compatible              ->   0     [MEASURED ×2]
find /sys/firmware/devicetree/base -name compatible  -> 256
```
`cat` on the very same `/proc/device-tree` paths works. `@95emulator` got a **"zero
assigned-clocks"** reading from this before sanity-checking the counter. **An instrument that returns
zero is indistinguishable from an absent property.** Use `/sys/firmware/devicetree/base`, and
**validate any DT counter against a property you already know is present** before trusting a zero.

---

## 7. Yocto / BSP naming — [UNKNOWN], pending confirmation

The first version hardcoded `MACHINE=imx95-19x19-lpddr5-evk` everywhere, including `deploy_dir`.
Evidence count across the fleet's i.MX95 repos:

| string | local hits | note |
|---|--:|---|
| `imx95-19x19-frdm-pro` | **68** | the live DTB basename on this board [MEASURED] |
| `imx95-15x15-evk` | 45 | a different package variant |
| `imx95-19x19-lpddr5-evk` | **1** | what the first version used everywhere |

> **⇒ The MACHINE name a build should use is [UNKNOWN] and must be confirmed, not defaulted.**
>
> **Negative evidence, 2026-09-12 — `@95emulator` [MEASURED]:** Kyle's local `imx-yocto-bsp` has
> **no machine conf and no DTS matching `frdm-imx95-pro`** — the PRO appears newer than that BSP
> snapshot. 🔴 **Do NOT adopt `imx95-15x15-lpddr4x-frdm`.** It exists (DTB `imx95-15x15-frdm`,
> `UBOOT_CONFIG imx95_15x15_frdm`) but it is a **different FRDM variant**; the PRO reports its own
> compatible. It is the plausible neighbour, which is precisely the class of error this file exists
> to stop — `@95emulator` nearly handed it over before checking the board, and said so.
>
> The DTB filename on the running board is measured; the *Yocto MACHINE* that produces it is a
> different string and has not been established. A BSP skill must **ask or detect**, never assume.
> **`compatible` is settled** (updated 2026-08-12, `@ollama_95_neutron` [MEASURED]):
> `fsl,frdm-imx95-pro fsl,imx95`, `model` = `NXP FRDM-IMX95-PRO`. The first version's
> `fsl,imx95-19x19-evk` is **wrong**; this file's earlier `fsl,imx95` was **right but incomplete**.
> ⚠️ **Matching only `fsl,imx95` also matches a non-FRDM i.MX95** — and the ARA240 being seated and
> the neutron DTB being booted are **instance** facts about one physical board, not SoC properties.
> Match the full string wherever that distinction matters.

---

## 8. Camera — [UNKNOWN]

The first version claimed BSP support for **OV5640, OV13858, OV2775, IMX219, IMX477** and hardcoded
`i2cdetect -y 4` / `-y 5` for CSI0/CSI1. **None of that is confirmed for this board.** The pipeline
shape is `Sensor (I²C) → MIPI CSI-2 RX → ISI → V4L2` [SOURCED].

**A camera skill must DETECT and REPORT, never assert:** enumerate with `v4l2-ctl --list-devices`,
match by **driver name, not device number** (`/dev/videoN` numbering is not stable across BSP updates
or USB camera insertion), and print what it found. *(Question posted to `imx95-media-test`.)*

---

## 9. Silicon validation record — 2026-08-12, by this repo

Everything in this section was measured **by these skills, on the board**, holding a hard lock, on a
censused-clean host (loadavg 0.06, no inference-shaped tenants). It is the drill that turns this
file from a transcription of other people's work into something this repo has verified.

**Confirmed exactly as documented** [MEASURED]:
`compatible = fsl,frdm-imx95-pro fsl,imx95` · `model = NXP FRDM-IMX95-PRO` · `soc_id i.MX95`
`revision 2.0` · 6 cores · gcc 15.2.0 · **kernel 6.18.20-2.0.0** · `/dev/neutron0` present ·
**both** delegates present at the sizes the fleet reported (`libneutron_delegate.so` 133128 B,
`liblitert_neutron_delegate.so` 329736 B) · ORT EP stack present (`libNeutronDriver.so` +
`libonnxruntime.so.1.24.3`) · `benchmark_model` at the documented path · `neutron-converter`
**absent on board** · ARA240 enumerated at `0000:01:00.0 [1e58:0002] rev 02` with
`uiodma` use-count **0 while idle** · `proxy_ara240` running (pid resolved via `/proc/PID/exe`) ·
`/var/run/proxy.sock` present · rootfs **100% full, 310 MB free**.

**`CmaTotal` 5177344 kB = 4.94 GiB** — the neutron DTB is booted, exactly as §2.3 says.
**`MemTotal` 16097084 kB** — consistent with 16 GB LPDDR [SOURCED].
**GPU devfreq node: `4d900000.gpu`** [MEASURED] — a real name for the search in `lib/sysfs.sh`.

### ✅ The two wrong-SoC delegates are genuinely ABSENT

`libethosu_delegate.so` and `libvx_delegate.so` do not exist on this board. So the original
implementation's six-path search would have found **nothing**, printed *"NPU inference will fall
back to CPU"*, and benchmarked six A55 cores. **The failure mode was not hypothetical.**

### ⭐ End-to-end gate validation — positive and negative control

| | converted (`yolov8n_eiq313.tflite`) | unconverted (`yolov8n_int8_for_neutron.tflite`) |
|---|---|---|
| placement | `1 nodes delegated out of 33 nodes with 1 partitions` | `0 nodes delegated out of **274** nodes with 0 partitions` |
| `CmaFree` | **dropped 8 MB** during the run | **did not move at all** (4993 → 4993 MB) |
| gate result | **exit 0**, number reported with tags | **exit 4, REFUSED, no number emitted** |

**Both gates agreed in both directions.** The unconverted model is the exact case the old code would
have reported as an NPU measurement.

### 📌 Verbatim placement string — and it differs by tool

```
INFO: NeutronDelegate delegate: 1 nodes delegated out of 33 nodes with 1 partitions.
```
Note **"NeutronDelegate delegate:"** — the word *delegate* twice. `@imx95-isp` measured
`NeutronDelegate: …` (once) via the native C harness. **So the prefix is NOT stable across tools**
— which retires the [INFERRED] hope in §2 and vindicates parsing tolerantly. Anchor on
*neutron…delegate…N nodes delegated*, never on an exact prefix.

### 🔴 Two card facts this run corrected

1. **`/run/media/root-mmcblk0p2` is 95% full — 555 MB free, not "~4 G".** It is still the right
   place to stage relative to a 100%-full rootfs, but the headroom is gone. **Check `df` first.**
2. **The PMIC thermal zones report a flat 105 °C placeholder** — see §2.6 below.

### ⚠️ One number that does NOT match the fleet, stated rather than reconciled

My yolov8n batch-1 run: **43.6 ms / 43.2 ms** across two runs (20 timed, 5 warmup).
The dossier's canonical figure: **32.08 ms** [MEASURED, 3-specimen tiebreaker].

**I am not overwriting theirs and not claiming a discrepancy.** The protocols differ (run count,
warmup, thermal history, possibly a different model file with the same name), and a 3-specimen
tiebreaker outranks my two runs. **It is recorded here as an open question, not a correction** —
the dossier itself notes an earlier 36.75 reading was a cool-board outlier, so this board's
batch-1 number is evidently sensitive to conditions nobody has fully pinned.

## 2.6 Thermal zones — the PMIC placeholder [MEASURED 2026-08-12]

| zone | type | reading | passive trip |
|---|---|--:|--:|
| 0 | `ana-thermal` | 51 °C | 105 °C |
| 1 | `a55-thermal` | **52 °C** | 105 °C |
| 2 | `pf09` | **105 °C (flat)** | 140 °C |
| 3 | `pf53_soc` | **105 °C (flat)** | 140 °C |
| 4 | `pf53_arm` | **105 °C (flat)** | 140 °C |

> 🔴 **The three PMIC zones are not temperatures.** They do not move, and they sit 35 °C below
> their own trip. **A `max(all zones)` compared against a hardcoded 80/85/95 °C limit refuses every
> run on a stone-cold board** — that is exactly what happened the first time our thermal gate met
> silicon.
>
> ✅ **Gate on the margin to each zone's OWN trip point**, and ignore trips ≤ 0 (unset trips park at
> INT_MIN on some drivers and yield a −2147519 margin). No zone-name allowlist is needed: 105-vs-140
> self-excludes as a 35 °C margin, while a genuinely hot A55 at 100-vs-105 is a 5 °C margin.

---

## 10. How to add a fact to this file

1. **Measure it on the board**, or cite the fleet artifact that did.
2. Add the row **with its tag**. If you cannot tag it, it is [UNKNOWN] — write that.
3. If it contradicts a row here, **do not silently overwrite** — state both, date them, and say
   which was re-measured. A fact that changed is more interesting than a fact that is right.
4. **Never promote a tag.** [SOURCED] does not become [MEASURED] because it was quoted twice, and
   [UNVERIFIED] does not become [MEASURED] because it has been sitting here a while.
