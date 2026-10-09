---
name: imx95-ara240
version: "1.0.0"
platform: imx95
accelerator: ara240
invoke_when:
  - "run a model on the ARA240"
  - "use the Kinara NPU"
  - "run an LLM on the board"
  - "is the second NPU there"
  - "run a .dvm model"
  - "how fast is the M.2 NPU"
  - "check if the ARA240 is busy"
requires:
  - bash
  - /usr/share/rt-sdk-ara240_2.1.1/nnapp/nnapp
safe: true
destructive: false
refuses_rather_than_degrades: true
opaque_resource: true
---

# imx95-ara240 — the second NPU

## Purpose

The FRDM-IMX95-PRO is a **dual-NPU board**. Alongside the on-SoC eIQ Neutron there is a
**Kinara ARA240** dataflow NPU on M.2 — ~40 TOPS [SOURCED], and unlike the Neutron it runs
**CNNs *and* a 7B LLM**.

**The first version of this repo did not know it existed.** Zero references to `ara240`,
`kinara`, or `nnapp` anywhere. Roughly half the board's AI capability — and the entire
generative-AI story — was simply missing.

## What it is

| | |
|---|---|
| Bus | PCI `0000:01:00.0`, ID `1e58:0002`, driver `uiodma` [MEASURED] |
| Runtime | `/usr/share/rt-sdk-ara240_2.1.1/` [MEASURED] |
| CLI | `nnapp` · model format **`.dvm`** (compiled **host-side** with the Kinara SDK) |
| Daemon | `proxy_ara240` (comm `kinara_main`) — owns the hardware, talks over `/var/run/proxy.sock` |
| Generative stack | `optimum-ara` — LLaMA, Qwen, **LLaVA VLM**, **Whisper** |
| Staged LLM | `/usr/share/llm/Qwen2.5-7B-Instruct/model.dvm` [MEASURED] |

> ⚠️ **You do not drive it via raw PCI.** The persistent daemon holds the BAR. Clients talk to
> the daemon. An earlier fleet note claiming "the ARA240 is NOT on PCI" was **wrong and has been
> corrected on silicon** — it *is* on PCI, you just don't program it that way.

---

## 🔴 THE RULE THAT GOVERNS THIS SKILL: OCCUPANCY IS HOST-UNDETECTABLE

An owner audit across **500 confirmed inferences** found that **every** host-side signal stays
flat whether the accelerator is busy or idle:

- `uiodma` lsmod use-count: **0 the entire time** — the daemon mmaps the BAR at idle *and*
  during inference, so the refcount never moves
- `:5000` ESTAB, BAR-`fuser`: no discriminating signal either

> **⇒ A check that prints "✅ ARA240 free" is reporting on a possibly fully-busy board.**
>
> So this skill **never claims the ARA240 is free.** It prints:
> `⚠️ ARA240 occupancy CANNOT BE DETERMINED FROM THE HOST — measured, not assumed.`
>
> That is not a limitation being apologised for — it is the correct output for an **opaque**
> resource. The board's fleet asset card is `class: opaque` for exactly this reason: **a dead
> owner means QUARANTINE, never auto-reap.** A reaper that "frees" this device is reaping
> someone's live 7B inference.

Candidate improvement, **untested**: connect a client peer to `/var/run/proxy.sock` during
inference and see whether the daemon reports session state. Until someone measures that, the
refusal stands.

---

## Usage

### CNN via `nnapp`

```bash
bash skills/imx95-ara240/scripts/check_ara240.sh          # presence, never "free"
bash skills/imx95-ara240/scripts/run_dvm.sh --model /usr/share/cnn/<model>.dvm
```

> **The random-input trick** [MEASURED]: to run a `.dvm` without preparing a preprocessed
> `.dat`, point the `nnapp` config's model `path:` at the `.dvm` and leave **`input_path:`
> empty**. `nnapp` then feeds random inputs. Useful for a throughput check; **useless for a
> correctness check** — random inputs cannot tell you the model is right.

### LLM via `optimum-ara`

```bash
pip3 install --break-system-packages --ignore-installed \
  /usr/share/python-wheels/optimum_ara-1.0.0-py3-none-any.whl \
  --extra-index-url https://download.pytorch.org/whl/cpu
```

Two gotchas that will each cost you a session [MEASURED]:

1. **`--ignore-installed` is REQUIRED** — Yocto's system packages have no `RECORD` file and pip
   aborts without it.
2. **Import order matters.** Use:
   ```python
   from transformers import AutoModelForCausalLM
   import optimum.ara            # <- this REGISTERS the backend
   ```
   Do **not** `from optimum.ara import AutoModelForCausalLM`.
3. Run **detached via a scp'd launcher script** — an inline `nohup` gets mangled. The first
   torch import on the A55 takes ~30 s and the log stays empty during it; that is not a hang.

---

## Measured performance — quote with tags, never bare

| workload | result | tag |
|---|--:|:--|
| yolov8n hardware | **296–298 IPS** (9.5× the Neutron) | [MEASURED] |
| yolov8 s/m/l/x | 142 / 54 / 26 / 16 IPS | [MEASURED] |
| yolov8n **deployed e2e** | **23.4 fps** | [MEASURED] |
| Qwen2.5-7B decode | **6.3 tok/s** on-accelerator | [MEASURED] |
| Qwen2.5-7B end-to-end | **5.36 tok/s** (short prompt) | [MEASURED] |
| NXP decode spec | 6.51 tok/s — corroborated within 3% | [SOURCED] |

> ### ⭐ The number that matters most is the one that looks worst
> Raw IPS is **9.5×** the Neutron. Deployed single-frame it collapses to **1.3×** (23.4 vs 18.1
> fps). The 42.8 ms frame decomposes as **~71% A55 host** (Python int8-quant + head-rebuild +
> letterbox + NMS), **~15%** ARA240 + PCIe DMA, **~10%** synchronous dispatch stall.
>
> **The bottleneck is the entry-tier host, not PCIe bandwidth.** The DMA moves ~739 KB in ~2 ms
> (~600 MB/s — far below the PCIe ceiling; latency/setup-bound, not bandwidth-bound). Even a
> zero-latency accelerator would land at ~31 fps, floored by the host.
>
> **Do not quote the 298 against the Neutron's 31 as a deployment claim.** One is an accelerator
> figure and one is a deployment figure, and mixing the tiers is how a 40-TOPS card gets sold on
> a number the customer will never see. Batching recovers it — but the natural batch source is
> **multi-camera** (N sensors, one tick, no added latency), not one camera buffered (which buys
> throughput with latency: per-frame 10 ms → 40 ms at batch 10).

---

## Caveats

- **`.dvm` models are compiled host-side.** There is no on-board compiler. You need a Kinara
  account for the host toolchain.
- **`df -h` before staging a `.dvm`.** `/run/media/root-mmcblk0p2` holds 555 M of 11 G; `/` holds
  8.7 G of 56 G, so the default outdir is the *tighter* filesystem. They are also different physical
  devices — the default is the **eMMC**, `/` is the **SD card** the board boots from. `/` shed 10 GB
  in the two days before this was written; do not plan against a figure from a doc (ground-truth §5).
- **This is an INSTANCE fact, not an "i.MX95" fact.** The ARA240 being seated and enumerated is
  true of *the board on the desk*. A same-model swap silently invalidates it, and there is no
  fingerprint yet. Re-verify after any hardware change.
- The ARA240 is a **dataflow NPU with no CNN op-cliff** — unlike the Neutron (CNN-only on the
  delegate path) and unlike the Hexagon (which cliffs on dilated conv).

## References

- `references/imx95-ground-truth.md` §3 — the ARA240 section with provenance tags
- `IMX95_BOARD_DOSSIER.md` §4.2 — the full sweep and the e2e decomposition
