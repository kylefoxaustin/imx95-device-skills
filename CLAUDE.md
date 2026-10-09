# CLAUDE.md — imx95-device-skills

> **Primary ingestion document. Read completely before executing any command on the board.**
>
> **Version 2.0 — a rewrite, not an edit.**

---

## 0. Read this section or you will reproduce the bug this repo was rewritten to fix

Version 1 of this repo was written by an agent with **no board access**. It was fluent,
well-organised, and substantially wrong — because when you ask an i.MX-shaped question without a
board, what comes back is the **i.MX93** and **i.MX8M Plus** answers.

The flagship defect, and it is worth understanding in full because every rule below descends from it:

> `imx95-npu-benchmark` searched **six** TFLite delegate paths. All six belonged to other SoCs —
> `libethosu_delegate.so` is Arm Ethos-U65 (**i.MX93**), `libvx_delegate.so` is VeriSilicon VX
> (**i.MX8M Plus**). On this board it found none, logged
> **`"NPU inference will fall back to CPU"`**, benchmarked six Cortex-A55 cores, and multiplied the
> result into a TOPS figure.
>
> **Every step worked exactly as written.** The warning was present and correct. It was also
> useless, because *a warning printed above a number is read as a caveat, and an exit code is read
> as a stop.*

The correct library is **`/usr/lib/libneutron_delegate.so`**. But the fix is not a string —
if it were, it would already have been fixed by the fleet doc that warns about this collision
**by name**. The fix is structural:

| # | rule | why |
|---|---|---|
| **1** | **REFUSE, never degrade.** A skill that cannot establish a fact exits non-zero. | v1 warned and continued. |
| **2** | **Measure PLACEMENT, never latency.** | All three Neutron failure modes return a plausible latency with no NPU in it. |
| **3** | **Assert-exists, never assert-exclusive.** | Hardcoding *one* path is the same brittleness as searching six wrong ones — there are **two** Neutron delegate files on this board. |
| **4** | **Never gate on an error string.** | The CMA-trap string *disappears* once the board is fixed, so a detector keyed on it silently passes on a healthy board and misses every other cause. |
| **5** | **Every number carries a provenance tag or is not emitted.** | `prov()` refuses an untagged value. |
| **6** | **The census is part of the measurement.** | "I measured it" is not provenance unless you also recorded what else was running. |

**All hardware facts come from `references/imx95-ground-truth.md`.** Nowhere else. Every entry there
is tagged **[MEASURED]** / **[DERIVED]** / **[SOURCED]** / **[UNVERIFIED]** / **[UNKNOWN]**, and where it says
[UNKNOWN] the skill **asks or refuses** — it does not default.

---

## 1. The board

Full table in `references/imx95-ground-truth.md` §1. The essentials:

| | | tag |
|---|---|---|
| Board | **FRDM-IMX95-PRO** (`fsl,frdm-imx95-pro fsl,imx95`) | [MEASURED] |
| SoC | i.MX95 **rev 2.0** | [MEASURED] |
| CPU | **6× Cortex-A55**, no big cluster (6 cores confirmed on silicon) | [MEASURED] |
| CPU freq domain | single shared cpufreq policy | [UNVERIFIED] — plausible, not traced to the dossier |
| GPU | **Arm Mali-G310** — graphics only, **OpenCL is an ICD stub** | [MEASURED] |
| NPU #1 | **eIQ Neutron-S**, `/dev/neutron0`, ~2–3 INT8 TOPS | dev [MEASURED] / TOPS [SOURCED] |
| NPU #2 | **Kinara ARA240** on M.2 — runs CNNs *and* a 7B LLM | [MEASURED] |
| OS | Yocto, **Linux 6.18**, gcc 15.2 on-board | [MEASURED] |
| 🔴 Two MMC devices | `/` = `mmcblk1p2` on the **58 G SD card** (56 G, 8.7 G free) — the board boots from the card. `/run/media/root-mmcblk0p2` is the **29.6 G eMMC** (11 G, 555 M free) and holds a *non-live* rootfs. | [MEASURED 2026-10-08] |
| ⚠️ Free space | **Volatile — `/` lost 10 GB in two days.** `df -h` before staging; `/` is currently the roomier by ~16×, the reverse of the August advice. | [MEASURED 2026-10-08] |

> **This is a DUAL-NPU board.** v1 did not know the second one existed — zero references to
> `ara240`, `kinara` or `nnapp`. Roughly half the board's AI capability, and the entire generative-AI
> story, was simply missing.

> **This is not a Jetson.** No `tegrastats`, `nvpmodel`, `nvidia-smi`, `jetson_clocks`, CUDA,
> TensorRT or cuDNN. Power/thermal/frequency come from sysfs; ML goes through eIQ or the Kinara
> runtime. The Mali GPU is **not** an ML target here — OpenCL is a stub.

---

## 2. Connection model

Claude Code runs on the **host** and SSHes to the board (`ssh imx95`, user **root**). Scripts use
board-side absolute paths. Never assume you are running locally unless `hostname` says `imx95evk`.

⚠️ **Dev images ship root with no password.** Set one before the board leaves the bench.

⚠️ **`df -h` before you choose an install path.** v1 said `git clone … /opt/imx95-device-skills`
unconditionally; the August correction said "use `/run/media/root-mmcblk0p2` instead". **Both are
standing answers to a question that only has a live one** — that partition holds 555 MB while `/`
holds 8.7 G, so the August advice now points at the *tighter* filesystem, and `/` shed 10 GB in the
two days before this was written (ground-truth §5). Measure, then choose.

⚠️ **The board is a sealed Yocto image with no working package feed.** Do not plan around
`opkg install`. Build on the host and `scp`. (`/usr/lib/libtensorflow-lite.so.2.19.0` exports the
full TFLite C API and gcc 15.2 is on-board, so a native harness is a real option — no headers ship;
link `-l:libtensorflow-lite.so.2.19.0`.)

---

## 3. Skills — what is actually on disk

| skill | status | what it does |
|---|---|---|
| **`imx95-npu-benchmark`** | ✅ **rewritten v2** | Neutron benchmark **gated on placement**. Refuses rather than reporting a CPU run. **21/21 eval**, incl. 3 CPU-spoof cases. **Validated on silicon.** |
| **`imx95-ara240`** | ✅ **new** | The second NPU. `nnapp`/`.dvm` + `optimum-ara`. **Refuses to claim the device is free** (occupancy is host-undetectable). |
| `imx95-diagnostic` | ⚠️ v1 | Board snapshot. Contains unverified constants — see §6. |
| `imx95-print-device-info` | ⚠️ v1 | Board identity one-liner. |
| `imx95-memory-audit` | ⚠️ v1 | Memory/CMA breakdown. **CMA is load-bearing here** — see §5. |
| `imx95-camera-setup` | ⚠️ v1, **[UNKNOWN] content** | Sensor list is unconfirmed — see §6. |
| `imx95-gpio-config` | ⚠️ v1 | GPIO via libgpiod. Expander facts corrected in ground truth §6. |
| `imx95-headless-mode` | ⚠️ v1 | Display enable/disable. |
| `imx95-package` | ⚠️ v1 | Package management — remember the feed is sealed. |
| `agents/imx95-perf-investigator.md` | ⚠️ v1 | Orchestrating agent. **Lives in `agents/`, not `skills/`.** |

**⚠️ v1 = not yet rewritten against ground truth. Treat its constants as unverified.**
**`imx95-npu-serve` was documented by v1 and does not exist.** Do not try to invoke it.

Every skill directory has `SKILL.md`. Only `imx95-diagnostic` and `imx95-npu-benchmark` have
`evals/`. v1 claimed `scripts/main.sh` was "always present" — **there are zero `main.sh` files in
this repo**; entry points are named for what they do.

---

## 4. ⭐ The Neutron rule — measure PLACEMENT, never latency

This is the single most important operational fact in the repo.

The Neutron has three failure modes and **all three return a plausible latency with no NPU in it.**
Timing cannot separate them. The delegated-node/partition count can — and it also tells you *which*
failure you have, which matters because they are fixed in three different places:

| placement | diagnosis | fixed at |
|---|---|---|
| `1 NeutronGraph / N nodes` | ✅ healthy — backbone fused | — |
| `1 of N`, N large | 🔴 converter trap | **CONVERT** time |
| `0 of N` | 🔴 CMA trap / unconverted model | **RUN** time |
| no placement line | 🔴 **cannot prove anything** | before quoting a number |

**The last row is reported as failure, not success.** A plausible number with no placement line has
exactly the shape of all three failures.

**A second, independent proof of execution** (`@imx95-isp`): **`CmaFree` DROPS across a real invoke**
(~2 MB) and does **not** move on a silent fallback. This depends on no log wording at all, which is
why it is a better gate than any error string.

**Two Neutron software stacks, two placement contracts — never cross-applied** (`@ollama_95_neutron`):
- **TFLite delegate** — `libneutron_delegate.so`; placement line
  `NeutronDelegate: N nodes delegated out of M nodes with K partitions`
  *(verbatim, including the ungrammatical "1 nodes" — a good regex anchor)*
- **ONNX Runtime Neutron EP** — `libonnxruntime.so.1.24.3` + `libNeutronDriver.so`; census is
  `offloaded_tensors` / `accelerated_nothing` from per-node EP assignment. **No shared signal.**

**The offline converter step is MANDATORY.** A plain INT8 tflite gives `0 nodes delegated out of 23`
[MEASURED]. `neutron-converter` is **not on the board** — convert on the host with the **standalone
eIQ Neutron SDK CLI 3.1.3**, never the pip `neutron_converter_SDK_*` packages (they stamp microcode
`0.0.0` and delegation collapses).

**Only `DEPTH_TO_SPACE` may legitimately fall to the A55.** Anything else in the fallback set is a
**topology regression, not a tuning knob** [MEASURED, `@imx95-isp`]. This is Neutron-**S** — use
`SupportedOperatorsS.md`, not the "C" doc.

---

## 5. Memory / CMA — a precondition for every Neutron measurement

`grep -i CmaFree /proc/meminfo` **before and after** every run.

The board boots **`imx95-19x19-frdm-pro-neutron.dtb`**, which adds a dedicated **4 GiB
`neutron_memory` shared-dma-pool** (`CmaTotal` 960 MiB → **4.94 GiB**). **Leave it.**
- Without it the ONNX EP's 2 GiB allocation fails against the stock 960 MiB pool → **silent all-CPU
  fallback**. That is why the Neutron was believed "CNN-only" for months.
- The dedicated pool is page-cache-immune, so it **retires** the CMA hazard for the ORT path. The
  **TFLite delegate path is believed to still draw from the 960 MiB `linux,cma` — [UNVERIFIED]**;
  nobody has measured which pool the delegate allocates from. The check stays because keeping it is
  the conservative choice, not because the reason is established.
- 🔴 **Never "restore the stock DTB" as a cleanup action.** It silently breaks the board into the
  CNN-only-looking state.

---

## 6. Known unknowns — ask, do not guess

Tracked in `../agentic-skills-imx/ROADMAP.md`.

- **Camera sensors [UNKNOWN].** v1 claimed OV5640/OV13858/OV2775/IMX219/IMX477 and hardcoded
  `i2cdetect -y 4/5`. None confirmed. `imx95-camera-setup` must **detect and report**, matching by
  **driver name, never `/dev/videoN`** (numbering shifts across BSP updates and USB insertions).
- **`liblitert_neutron_delegate.so` [UNKNOWN].** A second Neutron delegate is present (329736 B) and
  untested. Report it; do not load it silently.
- **Placement-line prefix is NOT stable across tools — now [MEASURED], and it differs.**
  `benchmark_model` prints `INFO: NeutronDelegate delegate: …` (the word *delegate* twice);
  `@imx95-isp`'s native C harness prints `NeutronDelegate: …`. Anchor on
  *neutron…delegate…N nodes delegated*, never on an exact prefix. `tflite_runtime` still unverified.
- **Thermal/frequency constants in the v1 skills [UNVERIFIED].**

---

## 7. Safety rules

**S1 — Never brick the board.** No `dd`/`mkfs`/`fdisk`/`flash_erase`/`mmc write` to any block
device, and no `fw_setenv`, without showing the exact command, stating what is overwritten, and
receiving explicit `yes`.

**S2 — Preserve your own connection.** Do not stop `sshd`, `systemd`, networking, `udev` or `dbus`
without confirmation. Killing `sshd` ends the session.

**S3 — Confirm persistent changes.** Anything surviving a reboot is destructive: U-Boot env, `/etc/`,
DTBs in `/boot`, fuses.

**S4 — Thermal.** Stop everything at ≥ 95 °C. Do not start a benchmark above 80 °C — a throttled run
is a real number for a board state nobody will remember when it is quoted.

**S5 — GPIO writes.** Check the protected-line list before writing. Power rails, eMMC reset, USB
VBUS and SoC reset can hang or brick the board. Native GPIO domain is **1.8 V**, board I/O 3.3 V.

**S6 — No speculative execution.** Do not run commands "to see what happens" on a shared board.

**S7 — Honour the reservation.** This board is a shared fleet resource (`/reserve imx95-frdm`). If
you do not hold the lock, you do not run. Release with a cleanup and print what you reaped.

**S8 — Never claim a resource is free when you cannot tell.** ARA240 occupancy is **host-undetectable
— measured, not assumed** (500-inference audit: every host-side signal stays flat). A check that
prints "✅ free" is reporting on a possibly fully-busy board. Treat as **opaque**: a dead owner means
QUARANTINE, never auto-reap.

---

## 8. Adding a skill

1. `mkdir -p skills/imx95-<name>/{scripts,evals}`; write `SKILL.md` with YAML front matter.
2. **Every hardware constant cites `references/imx95-ground-truth.md`.** Not there? Add it there
   first, with a tag — or mark it [UNKNOWN] and make the skill ask.
3. **Source `lib/neutron.sh` for anything NPU-related.** Use `prov()` to emit numbers; it refuses
   untagged values.
4. **Write the eval so it runs without the board.** `skills/imx95-npu-benchmark/evals/eval.sh` is the
   model: it feeds synthetic runtime logs to the safety gate and asserts exit codes. *A safety
   property you can only test on hardware you have to reserve is a safety property nobody tests.*
5. If you document it here, **it must exist**.

---

*imx95-device-skills v2.0 · NXP FRDM-IMX95-PRO · dual-NPU (eIQ Neutron-S + Kinara ARA240)*
*Hardware facts: `references/imx95-ground-truth.md` · Milestones: `../agentic-skills-imx/ROADMAP.md`*
