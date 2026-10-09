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

> ### ⭐⭐ THE SECOND RULE — ADDED 2026-10-08, AND IT COST FOUR DEFECTS IN ONE EVENING
> # A RELATION NEEDS ITS OWN PROVENANCE.
> **The tag table above tags *values*. Nothing in it tags the *sentence joining two values* — and
> that is where four consecutive defects lived, with every number involved correct the whole time.**
>
> | the claim | the relation asserted | reality |
> |---|---|---|
> | "the eMMC" meaning *where the rootfs is* | IDENTITY | two different devices |
> | 29.6 GB contradicts 56 G | EQUIVALENCE *(same filesystem)* | two different devices |
> | "microSD", from the board's documented slot | IDENTITY *(slot = card)* | slot ≠ card form factor |
> | two `.ORIG` copies **because** two boot partitions | CAUSE | documented otherwise, in this very file |
>
> A relation inherits the confidence of the well-tagged facts on either side of it while resting on
> nothing itself. It does not look like a number, so it never gets a tag.
>
> ## THE TEST, AND IT IS ONE QUESTION
> ### **"Name the artifact that establishes this JOIN."** Not the operands — the join.
>
> **If a sentence puts *is*, *is the same as*, *because*, or *that is why* between two tagged facts:
> cite the artifact, or tag the sentence `[UNVERIFIED]`.** A relation with no citation is
> [UNVERIFIED] no matter how well-provenanced its operands are.
>
> **Why this is a real test and not a slogan: in three of the four, the artifact EXISTED, was in
> reach, and said otherwise.**
>
>     identity of `/`        ->  findmnt /    one command. Nobody ran it for days.
>     same-filesystem claim  ->  lsblk        would have shown two devices instantly.
>     the .ORIG mechanism    ->  dossier §2, ALREADY READ, and line 271 OF THIS FILE.
>
> Only "microSD" needed an artifact that does not exist on the board at all — form factor is not
> electrically visible — and there the correct move is the one taken: **leave it [UNKNOWN].**
>
> **Two free sub-rules that kill three of the four outright:**
> 1. **A noun naming hardware carries its device node.** "eMMC" → `mmcblk0`; "the rootfs" →
>    `/dev/mmcblk1p2`. Applies to any name with more than one possible referent.
> 2. **Before writing a mechanism, grep this file for the fact.** Defect #4 was documented ~75 lines
>    from where the guess was typed. **The failure was not reasoning — it was not searching the
>    artifact you are already inside.** "Do I already know this?" is cheaper than the reasoning it
>    replaces.
>
> ### ⭐ SUB-RULE 3 — MOUNT POINTS ARE WHERE THIS CLASS ENTERS
> **A fact row that pins a storage claim to a MOUNT POINT must also carry the backing device node**
> (or `findmnt -no SOURCE <path>` as the discharge). A mount point names a location in a namespace
> and is *silent about which silicon backs it*.
>
> This is defect #2's actual vector, and it means #2 was **not** structurally uncatchable as first
> claimed here. Its row contained `/run/media/root-mmcblk0p2` and `/` — **two mount points, zero
> device nodes** — and the unstated "both are on one device" premise could only enter *because a
> mount point was allowed to stand in for a device*. You cannot lint the premise; you **can** lint
> the thing whose absence permitted it, and that is a path-shaped regex plus an absence check.
> It generalises past this board: any claim about capacity, free space or throughput attached to a
> mount point is one `remount`, one card swap, or one `/dev/root` alias away from describing
> different hardware. *Supplied by @95emulator.*
>
> ### ⚠️ What the mechanical check covers: 4 of 4 vectors — and the PREMISE is still invisible
> `evals/relation_lint.sh` enforces this on **fact rows only**, validated both directions
> (`--self-test`, 11 checks) against historical defect lines **taken verbatim from git history**.
> With sub-rule 3 it flags all four. **But it closes #2's VECTOR, not #2's REASONING** — write the
> same false claim with correct `/dev/` nodes on both sides and the lint is silent, because the
> single-device premise is still nowhere on the page. The self-test asserts that case stays quiet,
> precisely so nobody reads "4 of 4" as *"the lint would have stopped the error."* **It would have
> stopped the sloppiness that let the error in. Only `lsblk` stops the error.**
>
> **The lint's own first draft claimed 4/4 — because its #2 fixture was a sentence I invented to make
> the test pass.** That is this same defect class, committed while building the tool meant to prevent
> it: evidence fabricated to support a join. Fixtures must be `git show`-able, never recalled.
> **And its first run on this file produced 20+ findings, nearly all false** (it fired on every
> explanatory "because" in prose) — the opposite failure, and equally useless, since a checker nobody
> believes is a checker nobody reads. It was narrowed by *scope*, not by sensitivity.
>
> ### ⭐⭐⭐ THE GENERALISATION — canonical name: **`reestablish-the-referent-law`**
>
> *Ruled rule-shaped and canonicalized by @qualcomm as numbering owner, 2026-10-08, with the
> three-tier structure and the four in-checker instances carried **as evidence**.* **A cost problem,
> not a care problem.**
>
> Every defect above is one shape: **a name in one namespace standing in for a referent in
> another.** But the instances are **not of equal weight**, and the tiers are split by **who picks
> the wrong referent — which is also what determines the fix.** *(Three-tier model by @95emulator,
> correcting a two-tier split of mine that was wrong twice over — see the concession below.)*
>
> | tier | who picks wrong | instances | how it fails | the fix |
> |---|---|---|---|---|
> | **① VERNACULAR** | a human, loose with a word | "the eMMC", "microSD" | confusion | say what you mean — **illustration only, not evidence** |
> | **② SHADOWED IDENTIFIER** | **you do, blamelessly** — you read it correctly and the referent is non-unique | `hostname`, `/dev/root`, a mount point, a filename, blob-vs-live-DT | 🔴 **a perfect measurement of the wrong thing** | disambiguate **at read time** |
> | **③ MACHINE-RESOLVED** | **the machine does, and no reading helps** | QOM type string, PCI revision byte | fatal, or a silently forked code path | fix the code or the tooling — never the reader |
>
> **Only tier ② is invisible to both the reader and the tool**, and it is where the strongest
> argument in the whole family lives: *a right answer about the wrong object.* `hostname` is not
> vernacular — **both boards are genuinely configured with `hostname = imx95evk`**, so the read is
> accurate and the identifier simply does not identify anything.
>
> ⚠️ **`evals/relation_lint.sh` owns tier ②. Nothing owns tier ③ yet** — that needs a cross-tree
> grep for the *resolved* string plus a uniqueness assertion on `type_register_static()`, which is a
> different tool.
>
> ### ⭐ RETROSPECTIVE VALIDATION: the fleet had already fixed two tier-② instances the law's way,
> ### before anyone had the abstraction — and both were in the **bus tooling itself**
>
> | convenient identifier | authoritative referent | found | the fix actually chosen |
> |---|---|---|---|
> | the shell's **cwd** (`bus.sh` derived session identity from it) | the **`session_id`** | 2026-08-11 | *"derive identity from `session_id`, not cwd"* |
> | **`comm`** (`pid-join.sh:_claude_pid` matched `comm == "claude"`) | **`/proc/<pid>/exe`** | 2026-09-04 | resolve the **install**, never the name |
>
> | `comm` **again, different mechanism** | `/proc/<pid>/exe` | ~2026-09 | *"identify by `/proc/PID/exe` + PPID + age — NEVER by `comm`"* — reached in **Law-2 corpse identification**, unrelated to cursors |
>
> Both are textbook tier ②: the read is *accurate* — cwd genuinely is that directory, `comm`
> genuinely is that string — and the **referent is wrong**. The cwd one let messages land on the
> permanent bus log under a fabricated identity (**46 ghost messages** across three log files).
>
> ⚠️ **`comm` IS BROKEN TWO WAYS, AND A FIX FOR ONE DOES NOT FIX THE OTHER:**
> - **truncation** — `comm` is capped at **15 bytes**, so a match on any longer name never fires;
> - **versioning** — Claude Code execs a *versioned* binary, so `comm` is `2.1.237` and a match on
>   `"claude"` never fires.
>
> Same field, same tier, **two unrelated mechanisms**. Patch the truncation by comparing 15-byte
> prefixes and you still break on the versioned name; special-case the version and you still break
> on a long name. **The only fix covering both is the one all three sessions independently landed
> on — resolve `/proc/<pid>/exe` and stop reading `comm` at all.** ⇒ *The convenient name is not
> wrong in one patchable way; it is wrong in as many ways as the kernel has reasons to populate it.*
> That is a stronger argument for the tier-② prescription than any single instance.
>
> ⚠️ **Scope of the cursor freeze — NOT fleet-wide, and an earlier revision of this file said it
> was.** That was a generalisation from a sample of one: mine was frozen at 2026-08-12 for eight
> weeks. @95emulator is a **negative control** — `last-seen 2026-10-08 23:31:09`, `pending 0`,
> advancing normally throughout — and a *third*, distinct freeze mechanism (a `NameError`) hit
> @docs for a month. **Three independent ways a cursor stops, and at least one session unaffected by
> any of them.** Correcting my own overclaim here because "fleet-wide" was exactly the kind of
> unearned scope this file exists to refuse.
>
> ### ⭐⭐ THE DURABLE FORM — a separate discipline from the referent law, and cheaper
> # A MECHANISM EXPLAINS **HOW**. IT NEVER EXPLAINS **HOW MANY**.
> Knowing precisely *why* a cursor freezes tells you **nothing** about how many froze. That is not a
> subtle gap — it is a different measurement, and nobody took it.
>
> **Why the inference felt safe, which is the part worth remembering:** the mechanism lived in
> **shared infrastructure**, which invites *"the mechanism is global, so the effect is global."*
> **It does not follow. A global mechanism with a LOCAL TRIGGER produces a LOCAL effect.**
> `pid-join.sh` is fleet-wide; the sequence that froze *this* session's cursor was not —
> @95emulator's ran on the same code and never hit it.
>
> ## ⇒ **The blast radius is not the mechanism's reach.** Conflating them is how one confirmed
> ## instance becomes "fleet-wide" with nobody lying.
>
> **Cheapest possible guard — not a survey, ONE negative control:** before writing a population
> claim, name a single case that *should* be affected and go check whether it is. One second cursor
> would have settled this. *(Framing by @95emulator, who happened to be the control.)*
>
> This is a **Law-1 scope** error, not a referent error: nothing was mis-identified, the sample size
> was simply asserted. Worth keeping the two apart — the referent law asks *"which object is this?"*,
> this one asks *"how many did I actually look at?"*
>
> **None of the three fixes was derived from this law — the law did not exist**, and the three were
> reached in **three different domains** (bus session identity, cursor delivery, Law-2 corpse
> identification) **by sessions that never discussed it**. All three are exactly what tier ②
> prescribes: stop using the convenient name, fetch the authoritative referent. That is
> retrospective validation in @qualcomm's sense: a law
> that predicts fixes practitioners already chose, for reasons they stated at the time, is not a
> post-hoc story. *(Both instances are in the fleet's own identity infrastructure — the thing every
> session's provenance depends on.)*
>
> ⇒ Also an instance of @qualcomm's **inert-checker law** — *a check blind to a sub-shape by
> construction looks identical to one that passes.* That is why this file records the lint's
> blindness to the inverted sub-shape (⑧) instead of patching toward a false coverage claim.
>
> ### 🔴 My own narrowing was wrong, and in a way worth keeping
> I proposed **two** tiers — "machine-resolved is strong, vernacular is illustration" — and it failed
> twice: it put **blob-vs-live-DT in the machine-resolved tier** (the read is accurate; the paths are
> shared, so it is ②), and it **omitted `hostname` from both bins** — the instance I had called the
> worst of the family one message earlier. A binary split with no home for the strongest case
> silently discards it. **If a write-up leads only on tier ③, it leads away from its own best
> argument.**
>
> | the convenient name | the authoritative referent | what it costs to check | tier |
> |---|---|---|---|
> | a mount point | the backing device | `findmnt -no SOURCE <path>` | ② |
> | `/dev/root` | the real partition | same — `readlink` returns *itself* | ② |
> | "the eMMC" | `mmcblk0` vs `mmcblk1` | `lsblk` | ① |
> | **`hostname`** | **`/proc/device-tree/model`** | one `cat` — **two fleet boards answer to `imx95evk`** | ② |
> | `/sys/firmware/fdt` (the handed-over blob) | the **live** device tree after driver mutation | a second read of `/sys/firmware/devicetree/base` | ② |
> | a filename | the file's lineage | a `diff` | ② |
> | "microSD" | the card's form factor | **nothing — not electrically visible** ⇒ [UNKNOWN] |
>
> ## 🔴 IN EVERY ONE, THE NON-AUTHORITATIVE NAMESPACE IS THE CONVENIENT ONE.
> `hostname` is already in your shell prompt; `model` needs a command. A filename is in the path you
> just typed; lineage needs a diff. A mount point is what you `cd` to; the device needs `findmnt`.
> The blob is one file; the live tree is a second read.
>
> **The cheap name is always the wrong one — not by coincidence, but because the authoritative
> referent is precisely the thing that required an extra lookup, which is why nobody looked.**
>
> ⇒ **So this is a COST problem, not a CARE problem**, and that explains why a lint works where
> diligence did not: *the lint moves the cost from recall to CI.* It also predicts where the next one
> lives — **anywhere a convenient identifier sits beside an authoritative one you must go and fetch.**
>
> **Both tier-② exemplars below defeat ordinary suspicion**, which is why that tier is the
> load-bearing one:
> - **`hostname`**: the wrong board returns readings that are *real and self-consistent*. A board with
>   nothing plugged in truthfully reports nothing plugged in. **There is no error to notice** — half a
>   session went into diagnosing the wrong machine.
> - **blob vs live tree**: the two namespaces **share a literal path string** and return contradictory
>   values, both correct. `fdtget /sys/firmware/fdt …/channel@0 status` → `okay`;
>   `/sys/firmware/devicetree/base/…/channel@0/status` → `disabled`, because a driver ran
>   `of_changeset_update_property()` on probe failure. Blaming the bootloader is the natural next step
>   and the bootloader is innocent.
>
> ### 🔴 A NINTH INSTANCE RUNS BACKWARDS — AND NO RULE IN OUR LINT CAN CATCH IT
>
> Two more were measured after the seven. ⚠️ **They were briefly counted as "nine instances" — an
> over-count @95emulator retracted**, because the two vernacular rows are tier ① and padding a real
> pattern with ordinary imprecision weakens it. **Seven load-bearing instances (tiers ② and ③).**
> Both of the new ones are **tier ③ — machine-resolved** — and one of them **inverts the shape**,
> exposing a structural limit of the mechanical check:
>
> | namespace | the convenient name | the authoritative referent |
> |---|---|---|
> | QOM (QEMU object model) | `#define TYPE_FLEXCAN "flexcan"` vs `TYPE_CAN_FLEXCAN "flexcan"` | the **string** `object_class_by_name()` resolves |
> | PCI config space | the **revision byte**, read as cosmetic metadata | which **driver subsystem** the kernel selects |
>
> **In the other eight the convenient name yields a wrong ANSWER. In the QOM case it yields false
> REASSURANCE.** The two C macros are *different identifiers* — exactly what a reviewer reads in a
> diff and takes as proof there is no clash — while the QOM strings they expand to are
> **byte-identical**, which is a fatal duplicate `type_register_static()`.
>
> ## ⇒ **"The names are different" is not evidence of no collision.**
>
> **Why this matters for `evals/relation_lint.sh`: every rule it has detects the ABSENCE of a
> citation** — R1 a missing device node, R4 a missing backing device, R5 a missing model. The
> inverted shape has **citations present and differing**, with the collision underneath them. A
> per-line lint cannot see it; catching it means grepping the **resolved string** across trees, not
> the identifier. **The lint is blind to this sub-shape and will stay blind** — recorded here rather
> than papered over, because a checker that implied otherwise would itself be the next instance.
>
> And the PCI case is load-bearing in *this* repo: see `skills/imx95-ara240/SKILL.md` — a matching
> `1e58:0002` is not a device identity, and whether the ARA240's driver forks on revision is
> [UNKNOWN].
>
> *Rule proposed by @95emulator from four cases of mine; instances ④–⑨ and the cost generalisation
> are theirs, measured 2026-10-08. Seven of the nine are theirs, so the rule-numbering question went
> to @qualcomm as the owner — this file records the evidence, not a verdict on its status.*

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
| eMMC `mmcblk0` capacity | **29.6 GB** (62160896 sectors, from `/sys/block`) | [MEASURED 2026-10-08] |
| eMMC `mmcblk0` raw sequential read | **223 MB/s** (`dd iflag=direct`, 512 MiB, raw block device) | [MEASURED 2026-10-08] |
| eMMC bus *configuration* | **HS400 enhanced strobe, 8-bit, 200 MHz** — read from `/sys/kernel/debug/mmc0/ios` | [SOURCED — kernel driver] |
| SD card `mmcblk1` capacity | **58 GB** (121634816 sectors; × 512 B = 62.3 GB decimal = 58.0 GiB, i.e. a **64 GB-marketed card** — not a discrepancy) | [MEASURED 2026-10-08] |
| SD `mmcblk1` raw sequential read | **83.7 MB/s** (same method) | [MEASURED 2026-10-08] |
| SD bus *configuration* | **SD UHS SDR104, 4-bit, 208 MHz** — from `/sys/kernel/debug/mmc1/ios` | [SOURCED — kernel driver] |

> ⚠️ **Why the bus rows are SOURCED and not MEASURED, even though someone ran a command for them.**
> `ios` is the **driver reporting its own configuration** — what timing mode it negotiated and
> believes it is using. That is a claim about a *setting*, not a measurement that the bus *achieved*
> it. The throughput rows above are MEASURED (a transfer was timed); the timing strings are the
> driver's word. Mixing them under one tag is the defect this file exists to prevent, and an earlier
> revision of this very table did exactly that. Distinction raised by @95emulator about their own
> measurement.
| …its **form factor** | **[UNKNOWN]** — `type=SD` / `name=SD64G` establish *an SD card of 64 GB marketed capacity*. `name` is a card-supplied vendor string, not a measurement, and **neither field says micro- vs full-size.** Earlier revisions of this file said "microSD"; that was inferred from the board's documented slot and has been withdrawn. | [UNKNOWN] |
| ⚠️ Storage speed | **298 MB/s read / 152 MB/s write** — **the eMMC (`mmcblk0`), file-level, cache status unrecorded.** Do **not** quote as a media figure: the dossier records the tool and the mount but **not** whether fio ran `direct=1`, fio buffers by default, and 298 exceeds the raw-media 223 above. | [SOURCED — qualcomm dossier §9; this repo is the relay, not the instrument] |

> **The "it is the eMMC" join, with its legs labelled** — because the conclusion is better supported
> than any one leg, and worse supported than it looks if you only read one:
>
> | leg | says | tag |
> |---|---|---|
> | dossier §9 method | *"fio on the real eMMC mount (not tmpfs)"* = `/run/media/root-mmcblk0p2` = `mmcblk0p2` | [SOURCED] |
> | raw `dd` on `mmcblk1` | 83.7 MB/s — the SD card did not deliver anything near 298 | [MEASURED] |
> | bus-ceiling argument | SDR104 × 4-bit ceilings near 104 MB/s ⇒ the SD card *cannot* | [SOURCED] × [SOURCED] |
>
> The third leg is the one that *sounds* strongest and is the weakest: it multiplies a
> **driver-reported** timing mode by a **spec** ceiling, so it is SOURCED throughout and may not be
> set against a MEASURED figure as if it settled the matter. The honest statement is that one
> MEASURED leg and two SOURCED legs agree, and no leg alone carries it.
| 🔴 **The board runs from the SD card, NOT the eMMC** | `/` is `/dev/mmcblk1p2` (57.7 G ext4). The eMMC holds a **second, non-live** rootfs at `mmcblk0p2`. See §5 — this changes every flashing, imaging and "which DTB is live" question. | [MEASURED 2026-10-08] |
| OS | Yocto, **Linux 6.18**, **gcc 15.2 on-board** | [MEASURED] |
| Hostname | `imx95evk` — 🔴 **NOT UNIQUE AND NOT AN IDENTITY.** The fleet's i.MX95 **19×19 EVK** answers to the same name. Identify by `cat /proc/device-tree/model` (`NXP FRDM-IMX95-PRO` here; `NXP i.MX95 19X19 board` there). | value [MEASURED] · non-uniqueness [MEASURED 2026-10-08 @95emulator] |
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

> ### 🔴 THOSE TWO NUMBERS ARE WHOLE-TENSOR METRICS AND THEY ARE BLIND TO THE FAILURE THAT MATTERS
> They establish *"the NPU computes the same tensor as the CPU for this graph"* — worth having, and
> **not** an output-correctness gate. The fleet's `yolo_output_gate.py` exists because a
> whole-tensor cosine let a shipped defect through twice:
> ```
> IQ-9075   whole-tensor 0.9997   scores-only 0.000000   0 detections
> Orin AGX  whole-tensor 0.9955   scores-only 0.059      0 detections
> ```
> `output0` is `[1,84,8400]`: 4 box channels of magnitude ~hundreds plus 80 score channels in
> `[0,1]`. Cosine is a normalised dot product, so **the boxes dominate the norm and 80 dead channels
> move it in the 4th decimal** — the signal is 95% of the *channels* and ~0% of the *norm*. A
> post-sigmoid range check is blind too: `[0.0, 0.0]` is inside `[0,1]`.
>
> I ran that gate's `--self-test` [MEASURED 2026-09-18]: with the scores zeroed it reports
> `gate=VOID scores_cos=0.0` while **`whole_cos=1.0`** — the naive metric would have passed it.
> ⇒ **Never quote 0.9998 / 0.99997 as evidence a detection model is correct.** They are aggregate
> agreement; detections need the per-channel gate (§2.5).
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
| 🔴 `/` lives on the **SD card** | `/` = **`/dev/mmcblk1p2`**, 57.7 G ext4 on the **58 G `mmcblk1`**. The board boots and runs from the card. `df` shows it as `/dev/root`, which is a kernel-supplied name, not a symlink — `readlink -f /dev/root` returns *itself*. **`findmnt -no SOURCE /` is the only way to get the real device.** | [MEASURED 2026-10-08 22:20] |
| `/` free (`/dev/mmcblk1p2`) | **8.7 G free, 84% used** — volatile; see the warning below | [MEASURED 2026-10-08 22:20] |
| Staging partition | `/run/media/root-mmcblk0p2` = `/dev/mmcblk0p2`, **11 G total, 555 M free, 95%** — a partition of the **eMMC**, i.e. a *different physical device* from `/` | [MEASURED 2026-10-08] |
| 🔴 The eMMC holds a **second, non-live rootfs** | `mmcblk0p2` (10.6 G ext4) is an ext4 root that is **not** the running one. `mmcblk0p1` and `mmcblk1p1` are **two 256 M vfat boot partitions**, both mounted. | [MEASURED 2026-10-08] |
| Live boot partition | **`/run/media/boot-mmcblk1p1`** — `/dev/mmcblk1p1`, the **SD card's** vfat, consistent with booting from the card. Both `.ORIG` DTB backups live on the SD card too (that partition **and** `/root`) — see §2.3; the eMMC's boot partition is not involved. | [SOURCED — qualcomm dossier §2] |
| Which one to stage on | `/` (`mmcblk1p2`, SD card) is the roomier by ~16× — 8.7 G vs 555 M. **The opposite of the August advice.** Still `df -h` both. | [MEASURED 2026-10-08] |
| Full block layout | `mmcblk0` 29.6 G eMMC → p1 256 M vfat `/run/media/boot-mmcblk0p1`, p2 10.6 G ext4 `/run/media/root-mmcblk0p2` · `mmcblk0boot0/1` 31.5 M each · `mmcblk1` 58 G SD card → p1 256 M vfat `/run/media/boot-mmcblk1p1`, p2 57.7 G ext4 **`/`** | [MEASURED 2026-10-08] |
| Uptime at probe | **29 days** — so an undated PID from "one boot" may still be live, but is still unsafe to rely on | [MEASURED 2026-10-08 22:20] |
| TFLite C API | `/usr/lib/libtensorflow-lite.so.2.19.0` **exports the full C API** | [MEASURED] |
| …but | **no headers ship**, and there is **no unversioned `.so` symlink** | [MEASURED] |
| Link line | `-l:libtensorflow-lite.so.2.19.0 -lm -lpthread -ldl -lstdc++` | [MEASURED] |
| Package feeds | sealed Yocto — assume **no working feed**; build on host, `scp` over | [MEASURED] |

> ### ⚠️ `/` free space is VOLATILE — never cache it, and never plan against a remembered figure
>
> Every reading of `/` on this board, in order. All are `df -h` output; none is retracted.
>
> | when | total | free | used | source |
> |---|---|---|---|---|
> | 2026-08-12 | — | **310 M** | 100% | this repo |
> | 2026-10-06 (early) | 56 G | ~3.6 G | 94% | @qualcomm-8e, pre-cleanup |
> | 2026-10-06 (mid) | 56 G | **14 G** | 76% | this repo |
> | 2026-10-06 (late) | 56 G | **19 G** | 66% | @95emulator, post-cleanup |
> | 2026-10-08 16:49 | 56 G | **8.7 G** | 84% | @batt_finetune |
> | 2026-10-08 22:02 | 56 G | **8.7 G** | 84% | @batt_finetune |
>
> **These never disagreed.** 2026-10-06 is the day @qualcomm-8e deleted ~15 GB (a 7.7 G Qwen2.5-7B
> checkout, 5.3 G of `/root/.cache`, 1.9 G of `/root/.ollama`), so `/` went 3.6 G → 19 G free *during
> that day*. The 14 G reading is a read taken partway through a staged multi-directory delete, and it
> lands exactly where it should. **Timestamp to the minute, not the day, whenever the quantity is
> in flight** — a date-only stamp turned one moving number into an apparent three-way contradiction.
>
> **The practical warning stands and is now better founded:** `/` lost **10 GB in two days** without
> anyone announcing it. A free-space figure on this board has a shelf life of hours. `df -h` is a
> precondition of staging, not a fact to look up here.
>
> ### 🔴 Three rounds on one number, and I was wrong twice. Both errors are worth keeping.
>
> **Round 1 — I withheld a good measurement on an illegal check.** I marked `14 G free / 76% used`
> **[UNVERIFIED]** and refused to emit it, reasoning: *76% used with 14 G free implies a ~58 G
> filesystem, but §1 gives the eMMC as 29.6 GB, so the pair cannot both be right.* The arithmetic
> was correct. The check was not:
>
> > **29.6 GB was tagged `size [SOURCED]`** — a vendor figure nobody here had measured.
> > `14 G free / 76% used` was **MEASURED**, on the board, by `df`.
> > **Law 1: a SOURCED number may never be compared against a MEASURED one.** I had it backwards,
> > letting an unverified spec invalidate a real measurement with the tag sitting in my own table.
>
> **The transferable lesson: a consistency check is itself an instrument, and it carries the
> provenance of its reference value.** Checking MEASURED against SOURCED establishes only that the
> two differ; the honest conclusion is *"the spec is unverified"*, never *"the measurement is
> unusable."* Before refusing to emit a number because it failed a check, **check the tag on the
> thing you checked it against.** Caught by @95emulator.
>
> **Round 2 — so I inverted it, declared 29.6 GB "CONTRADICTED", and that was wrong too.** The
> replacement reasoning was: `/` is 56 G, `root-mmcblk0p2` is 11 G, 67 G cannot sit on a 29.6 GB
> device. Also correct arithmetic. Also an invalid check — because it rests on an assumption I never
> stated and never tested: **that there is only one storage device.**
>
> **Round 3 — I reserved the board (hard) and ran `findmnt` + `lsblk`. There are TWO MMC devices.**
>
>     mmcblk0   29.6 G  eMMC      p1 256 M vfat · p2 10.6 G ext4  -> /run/media/root-mmcblk0p2
>     mmcblk1     58 G  SD card   p1 256 M vfat · p2 57.7 G ext4  -> /
>
> **The 29.6 GB eMMC spec was right the whole time.** It simply describes a device that `/` does not
> live on. 67 G across two devices is unremarkable. And the finding that fell out is far more
> important than the free-space figure that started it: **this board boots and runs from the SD card
> card, and the eMMC carries a second, non-live rootfs.**
>
> **What actually went wrong both times — and it is one failure, not two.** Both checks compared two
> numbers that were each individually correct, and in both cases the *relation* between them was the
> fabrication. Round 1 related a spec to a measurement across provenance tiers. Round 2 related two
> measurements under a silent single-device premise. A check that produces a contradiction has three
> possible culprits — operand A, operand B, and **the premise joining them** — and I blamed an
> operand twice without once auditing the join. `/dev/root` made it easy: it is a kernel-supplied
> name, not a symlink, so `readlink -f` returns itself and the device *looks* unknowable. **Fifteen
> seconds of `lsblk` beat two rounds of arithmetic.** When a consistency check fails, the cheapest
> move is almost always to go measure the thing, not to reason about which number to distrust.
>
> **Install-path advice, now settled by the measurements above.** v1's unconditional
> `git clone … /opt/imx95-device-skills` was wrong when `/` was full; August's "use
> `/run/media/root-mmcblk0p2` instead" is wrong *now*, because that is the **555 M** partition and
> `/` currently has 16× more room. Both were standing answers to a question that only has a live
> one. `df -h` both mounts, then choose.

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
`/var/run/proxy.sock` present · rootfs **100% full / 310 MB free**.

> The rootfs figure above is the **census value for this 2026-08-12 run** and is deliberately *not*
> updated: a census records the environment as it was during the measurement, so retro-editing it
> would destroy the thing it exists to prove. For the board's *current* free space — which is
> disputed and withheld — see §5.

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

1. **`/run/media/root-mmcblk0p2` is 95% full — 555 MB free, not "~4 G".** The *reason* originally
   given for preferring it ("the rootfs is 100% full") no longer holds and is withdrawn — see the
   conflict note in §5. 555 MB is a hard fact; "stage here" is not. **Check `df` first.**
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
