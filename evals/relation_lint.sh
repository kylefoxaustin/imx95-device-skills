#!/usr/bin/env bash
# evals/relation_lint.sh
#
# Partial mechanical enforcement of the SECOND provenance rule in
# references/imx95-ground-truth.md §0:
#
#     A RELATION NEEDS ITS OWN PROVENANCE.
#     "Name the artifact that establishes this JOIN."
#
# ─── WHAT THIS CATCHES: ALL 4 VECTORS. NONE OF THE REASONING. ────────────────
#
# Validated retrospectively against the four real 2026-10-08 defects, each line
# taken VERBATIM FROM GIT HISTORY (not paraphrased — see the note below):
#
#   #1  8bd1f17 L67   "| Storage | eMMC, 29.6 GB, ... |"              R1
#   #2  3f7d646 L68   "`/` alone measures 56 G and
#                      /run/media/root-mmcblk0p2 11 G: 67 G ..."      R4
#   #3  (pre-fix)     "eMMC 29.6 GB [SOURCED], microSD slot ..."      R2
#   #4  23da184 L436  "...This is almost certainly why the `.ORIG`
#                      DTB backups were reported in two places."      R3
#
# 🔴 #2 WAS FIRST DOCUMENTED HERE AS STRUCTURALLY UNCATCHABLE. THAT WAS WRONG,
# and @95emulator supplied the correction: you cannot lint the PREMISE, but you
# CAN lint the thing whose absence PERMITTED it. #2's row carried two MOUNT
# POINTS and zero device nodes; the unstated "both are on one device" premise
# could only enter because a mount point was allowed to stand in for a device.
# R4 closes that vector mechanically.
#
# ⚠️ BUT R4 DOES NOT CLOSE #2's REASONING, AND THE DISTINCTION MATTERS.
# Write the same false claim with correct `/dev/` nodes on both sides and this
# script is SILENT — the single-device premise is still nowhere on the page.
# Self-test (b1) asserts exactly that case stays quiet, so "4 of 4" can never be
# read as "the lint would have stopped the error". It would have stopped the
# sloppiness that let the error in. Only `lsblk` stops the error.
#
# ⚠️ THE FIRST VERSION OF THIS SCRIPT CLAIMED 4/4 — because its #2 fixture was a
# PARAPHRASE invented to make the test pass ("...that is why the figure is
# unusable", a sentence that never existed in the repo). That is the same defect
# class as the four it polices: evidence fabricated to support a join. The
# fixtures below are now `git show`-able. If you add a fixture, take it from
# history, never from memory.
#
# ─── BOTH-DIRECTION VALIDATION ───────────────────────────────────────────────
# @qualcomm: "a checker tuned until it's quiet is worse than none" — silence gets
# read as evidence. `--self-test` therefore asserts BOTH that the lint fires on
# all 4 historical defect VECTORS AND that it stays silent on legitimate lines
# that look similar. An earlier R3 fired on every explanatory "because" in prose
# — 20+ findings, almost all false — which is the opposite failure and just as
# useless, because a checker nobody believes is a checker nobody reads.
#
# ─── SCOPE, STATED SO A CLEAN RUN CANNOT BE MISREAD ──────────────────────────
# ALL rules check TABLE ROWS ONLY (lines beginning with `|`) — the fact rows a
# script or skill actually reads a constant out of. Explanatory prose is NOT
# checked, deliberately: a "because" in a paragraph is normal writing.
# ⇒ A clean run means "no unprovenanced relation in a FACT ROW". It does not mean
#   the document is free of unprovenanced relations, and it cannot see an
#   unstated premise at all.
#
# Exit: 0 clean · 1 findings · 2 self-test failed · 3 usage/missing file

set -euo pipefail

# Hardware nouns with MORE THAN ONE possible referent on this board.
_AMBIGUOUS_NOUN='eMMC|rootfs|root filesystem|SD card|the card'

# Anything that pins the referent discharges R1: a device node, the kernel's own
# name for it, a resolving command, or an explicit "we do not know".
#
# ...plus one scope exemption, added after the first run on bsp-platforms-catalogue.md:
# a row whose value is a FILENAME that merely contains "emmc" (`frdm-imx95-emmc.uuu`)
# makes no claim about storage at all — the noun is part of an identifier. Demanding a
# device node there is a false positive, and 2 of the first 8 findings on that file were
# exactly this. Narrow, and deliberately keyed on the file EXTENSION rather than on the
# substring "emmc", so it cannot be stretched to excuse a real storage claim.
#
# Second exemption, added after the first run over imx95-bsp-skills' SKILL.md
# files: in a BUILD context "rootfs" names an ARTIFACT BEING PRODUCED, not a
# mounted filesystem on a device — `bitbake <image_recipe>` / "rootfs changes" /
# `<recipe>-<machine>.rootfs.ext4`. Demanding a device node there is a category
# error of the lint's own making: the word is in a different namespace again,
# which is funny but still a false positive. Keyed on build vocabulary.
_FILENAME_ROW='\.uuu|\.dts|\.dtsi|\.dtb|\.bin|\.wic|\.sdcard|\.ext4|\.tar|\.manifest'
_BUILD_CONTEXT='bitbake|image_recipe|<machine>|recipe|yocto|DISTRO|MACHINE='
# ── Mount points are where this whole class ENTERS (R4, @95emulator) ─────────
# A mount point names a location in a namespace and is SILENT about which
# silicon backs it. Defect #2's real row contained `/run/media/root-mmcblk0p2`
# and `/` — two mount points, zero device nodes — and that is precisely what let
# the unstated "both are on one device" premise in.
#
# 🪤 AND IT EXPOSED A BUG IN THIS SCRIPT: `/run/media/root-mmcblk0p2` is a mount
# DIRECTORY whose name happens to contain "mmcblk0p2", so the naive
# `mmcblk[0-9]` discharge matched it and R1 fell silent. The checker was fooled
# by a string RESEMBLING a device node — the same name-vs-referent confusion it
# exists to catch. Fix: strip mount paths from the line BEFORE looking for a
# device node, so only a real `/dev/...` or a bare token can discharge.
_MOUNT_PATH='/run/media/[A-Za-z0-9_.-]*|/mnt/[A-Za-z0-9_.-]*|/boot[A-Za-z0-9_./-]*'
# A storage claim MUST carry a MAGNITUDE. The first version accepted the bare
# words "free", "full" and "capacity", and immediately produced a false positive
# on the ARA240 row: *"Refuses to claim the device is free (occupancy is
# host-undetectable)"* — where "free" means an UNOCCUPIED NPU, not disk space.
# A word-sense collision, which is this file's own subject arriving one more
# time. Requiring a number makes the sense unambiguous.
_STORAGE_CLAIM='[0-9][0-9.]* ?(G|GB|GiB|M|MB|MiB|TB)\b|MB/s|[0-9]+ ?% used|[0-9]+ sectors'
# Mount-point tokens. NOTE the bare backtick-slash-backtick form is NOT listed:
# it matched the path separator inside `` `nnapp`/`.dvm` `` and read a code-span
# separator as the root filesystem. Only a cell-leading `/` or `/` followed by a
# verb of possession counts.
_MOUNT_TOKEN="$_MOUNT_PATH"'|^\| *`/` |`/` (free|is|has|lost|holds|measures|shed)|the rootfs|rootfs is'

# Strip mount paths, then ask whether a REAL device node remains.
_strip_mounts() { printf '%s' "$1" | sed -E "s#($_MOUNT_PATH)##g"; }
_REAL_NODE='/dev/[a-z]|`mmcblk[0-9]|`/dev|mmcblk[0-9]p?[0-9]?`|findmnt'

# NOTE the tags are matched WITHOUT a closing bracket. The first version required
# `\[UNVERIFIED\]` exactly, so a tag that carried its reason — `[UNVERIFIED: no
# 15x15 board in the fleet]`, which is the better way to write it — failed to
# discharge the rule and the lint kept firing on a correctly-tagged row. A
# checker that only accepts the terse form of a tag pushes authors toward the
# less informative one.
_NODE_CITED='mmcblk[0-9]|mmc[0-9]|/dev/root|nvme[0-9]|findmnt|lsblk|\[UNKNOWN|\[UNVERIFIED'

# ── R5: hostname is not an identity ──────────────────────────────────────────
# TWO physically different boards in the fleet answer to `imx95evk` (this
# FRDM-IMX95-PRO and an i.MX95 19x19 EVK). The failure mode is the nastiest in
# the family: the wrong board returns readings that are REAL and SELF-CONSISTENT
# — a board with nothing plugged in truthfully reports nothing plugged in — so
# there is no error to notice and a whole investigation can finish clean against
# the wrong machine. Measured by @95emulator after losing half a session to it.
# Discharge: name /proc/device-tree/model, or say outright it is not unique.
_HOSTNAME_TOKEN='imx95evk|\bhostname\b'
_MODEL_CITED='/proc/device-tree/model|device-tree model|NOT UNIQUE|not an identity|NOT AN IDENTITY|non-uniqueness|FRDM-IMX95-PRO'

# Not discharge-able: no artifact on the board establishes card form factor.
_BANNED_TOKEN='microSD|micro-SD'
# ...except the rule's own prose, which must be able to name what it forbids.
_BANNED_EXEMPT='withdrawn|banned|forbidden|neither field says|NOT CAUGHT|said "microSD"|slot = card'

# A HEDGED CAUSE is the fingerprint of an invented mechanism. A bare "because" in
# a fact row is usually a real citation; "almost certainly why" is a guess.
_HEDGE='almost certainly|most likely|likely|probably|presumably|no doubt|doubtless|suggests that|it seems'
_CAUSE='because|why|the reason|explains|accounts for|which is how'

# An artifact citation discharges R3.
_ARTIFACT_CITED='§|dossier|/sys/|/proc/|/run/|/root/|commit [0-9a-f]{7}|\[SOURCED|\[UNVERIFIED\]|\[UNKNOWN\]'

FINDINGS=0

_report() {   # <file> <lineno> <rule> <why> <line>
    printf '%s:%s: [%s] %s\n' "$1" "$2" "$3" "$4"
    printf '    %s\n' "$(printf '%s' "$5" | cut -c1-150)"
    FINDINGS=$((FINDINGS + 1))
}

lint_file() {   # <path>
    local f="$1" n=0 line bare
    [ -f "$f" ] || { echo "relation_lint: no such file: $f" >&2; return 3; }
    while IFS= read -r line; do
        n=$((n + 1))
        # Fact rows only. Everything else is prose and out of scope by design.
        case "$line" in \|*) ;; *) continue ;; esac

        if printf '%s' "$line" | grep -qiE "$_BANNED_TOKEN" \
           && ! printf '%s' "$line" | grep -qiE "$_BANNED_EXEMPT"; then
            _report "$f" "$n" R2 \
              'card form factor is not electrically visible — no artifact can establish "microSD"' "$line"
        fi

        if printf '%s' "$line" | grep -qiE "$_HEDGE" \
           && printf '%s' "$line" | grep -qiE "$_CAUSE" \
           && ! printf '%s' "$line" | grep -qE "$_ARTIFACT_CITED"; then
            _report "$f" "$n" R3 \
              'hedged causal claim with no artifact cited — an invented mechanism, or cite the source' "$line"
        fi

        # R1 — ambiguous hardware noun with no device node. Mount paths are
        # stripped first: a mount DIRECTORY named after a device is not a device.
        local bare; bare="$(_strip_mounts "$line")"
        if printf '%s' "$line" | grep -qiE "$_AMBIGUOUS_NOUN" \
           && ! printf '%s' "$bare" | grep -qE "$_NODE_CITED" \
           && ! printf '%s' "$line" | grep -qiE "$_FILENAME_ROW" \
           && ! printf '%s' "$line" | grep -qiE "$_BUILD_CONTEXT"; then
            _report "$f" "$n" R1 \
              'hardware noun with >1 possible referent and no device node' "$line"
        fi

        # R5 — hostname used as board identity with no device-tree model cited.
        if printf '%s' "$line" | grep -qiE "$_HOSTNAME_TOKEN" \
           && ! printf '%s' "$line" | grep -qiE "$_MODEL_CITED"; then
            _report "$f" "$n" R5 \
              'hostname is NOT a board identity — two fleet boards answer to imx95evk; cite /proc/device-tree/model' "$line"
        fi

        # R4 — a storage claim attached to a MOUNT POINT with no backing device.
        # This is the vector defect #2 came in through: a mount point standing in
        # for a device. Generalises past this board — any capacity, free-space or
        # throughput claim pinned to a mount point is one remount, one card swap
        # or one /dev/root alias away from describing different hardware.
        if printf '%s' "$line" | grep -qE "$_MOUNT_TOKEN" \
           && printf '%s' "$line" | grep -qiE "$_STORAGE_CLAIM" \
           && ! printf '%s' "$bare" | grep -qE "$_REAL_NODE" \
           && ! printf '%s' "$line" | grep -qE '\[UNKNOWN|\[UNVERIFIED'; then
            _report "$f" "$n" R4 \
              'storage claim pinned to a MOUNT POINT with no backing device — add the device node or `findmnt -no SOURCE <path>`' "$line"
        fi
    done < "$f"
    return 0
}

_run_one() {   # <text> -> sets FINDINGS; echoes nothing
    local t="$1" tf
    tf="$(mktemp)"
    printf '%s\n' "$t" > "$tf"
    FINDINGS=0
    lint_file "$tf" >/dev/null 2>&1 || true
    rm -f "$tf"
}

self_test() {
    local pass=0 fail=0

    # (a) REAL historical defect lines, verbatim from git history.
    local d1 d3 d4
    d1='| Storage | eMMC, 29.6 GB, **298 MB/s read / 152 MB/s write** | read/write [MEASURED], size [SOURCED] |'
    d3='| Storage | eMMC 29.6 GB, microSD slot | size [SOURCED] |'
    d4='| 🔴 The eMMC holds a **second, non-live rootfs** | `mmcblk0p2` (10.6 G ext4) is an ext4 root that is **not** the running one. `mmcblk0p1` and `mmcblk1p1` are **two 256 M vfat boot partitions**, both mounted. This is almost certainly why the `.ORIG` DTB backups were reported "in two places". | [MEASURED 2026-10-08] |'

    echo "--- (a) must FLAG historical defects #1, #3, #4 (R1/R2/R3)"
    for spec in "1:$d1" "3:$d3" "4:$d4"; do
        _run_one "${spec#*:}"
        if [ "$FINDINGS" -gt 0 ]; then
            echo "  [PASS] defect #${spec%%:*} flagged"; pass=$((pass + 1))
        else
            echo "  [FAIL] defect #${spec%%:*} SLIPPED — do not ship"; fail=$((fail + 1))
        fi
    done

    # (b) #2, now CAUGHT by R4 — via its vector, not its premise.
    #
    # This assertion was inverted on 2026-10-08. It previously asserted #2 stays
    # QUIET and said: "if a future edit makes it fire, the header's 3-of-4 claim
    # is stale and must be updated." @95emulator then supplied the rule, the
    # fixture duly failed, and the header was updated. That is a fixture doing
    # its job — recording a limitation so precisely that removing the limitation
    # breaks the test. Note the ORIGINAL defect text is tagged [UNVERIFIED], so
    # R4's tag discharge is removed here to test the row as it would read
    # WITHOUT that tag, which is how it was first written.
    echo "--- (b) defect #2 — now CAUGHT by R4, via its vector (mount point for device)"
    _run_one '| ⚠️ Storage size | ~~eMMC 29.6 GB~~ — **CONTRADICTED.** `/` alone measures **56 G** and `/run/media/root-mmcblk0p2` **11 G**: 67 G of mounted filesystem cannot sit on a 29.6 GB device. | [MEASURED] |'
    if [ "$FINDINGS" -gt 0 ]; then
        echo "  [PASS] #2 flagged — two mount points, zero device nodes"; pass=$((pass + 1))
    else
        echo "  [FAIL] #2 slipped — R4 regressed; the header claims it is caught"; fail=$((fail + 1))
    fi

    # (b1) The PREMISE itself is still unreadable, and that limit is permanent.
    # Same claim, correctly cited with real device nodes: the single-device
    # premise is still wrong, and nothing here can see it. R4 closes the VECTOR,
    # not the premise. Keep this asserting quiet so nobody reads 4-of-4 as
    # "the lint would have stopped the reasoning error".
    echo "--- (b1) the PREMISE stays invisible even when properly cited — permanent limit"
    _run_one '| Storage size | `/dev/mmcblk1p2` measures **56 G** and `/dev/mmcblk0p2` **11 G**: 67 G cannot sit on a 29.6 GB device. | [MEASURED] |'
    if [ "$FINDINGS" -eq 0 ]; then
        echo "  [PASS] premise invisible, as documented — R4 closes the vector, not the reasoning"
        pass=$((pass + 1))
    else
        echo "  [FAIL] unexpected finding — re-read what R4 is claiming to cover"; fail=$((fail + 1))
    fi

    # (b2) The filename exemption's KNOWN HOLE, asserted rather than hidden.
    # A row that contains BOTH a filename and a genuine bare storage claim is
    # exempted by R1 and slips through. Keyed on extension so it cannot be
    # stretched on purpose, but it is a real gap: a reviewer must not read a
    # clean run as covering rows that happen to name a .uuu/.dtb/.wic file.
    echo "--- (b2) filename exemption has a KNOWN HOLE — assert it, do not hide it"
    _run_one '| Flash target | use `frdm-imx95-emmc.uuu`; the eMMC is where the rootfs lives | [UNVERIFIED-ish] |'
    if [ "$FINDINGS" -eq 0 ]; then
        echo "  [PASS] hole confirmed present and documented (filename row exempts a real claim)"
        pass=$((pass + 1))
    else
        echo "  [FAIL] the hole is GONE — good, but this header documents it. Update the header."
        fail=$((fail + 1))
    fi

    # (a2) R5 — the hostname instance, from this repo's own pre-fix text.
    echo "--- (a2) must FLAG hostname-as-identity (R5)"
    _run_one '| Hostname | `imx95evk` | [MEASURED] |'
    if [ "$FINDINGS" -gt 0 ]; then
        echo "  [PASS] bare hostname row flagged"; pass=$((pass + 1))
    else
        echo "  [FAIL] hostname row slipped — two boards answer to it"; fail=$((fail + 1))
    fi

    echo "--- (c) must stay SILENT on legitimate fact rows"
    local g
    for g in \
      '| eMMC `mmcblk0` capacity | **29.6 GB** (62160896 sectors, from `/sys/block`) | [MEASURED] |' \
      '| SD bus configuration | **SDR104, 4-bit** — from `/sys/kernel/debug/mmc1/ios` | [SOURCED — kernel driver] |' \
      '| Live boot partition | `/run/media/boot-mmcblk1p1` — both `.ORIG` copies are there and in `/root`, per dossier §2 | [SOURCED] |' \
      '| …its form factor | **[UNKNOWN]** — neither field says micro- vs full-size | [UNKNOWN] |' \
      '| Rootfs device | `/dev/mmcblk1p2` via `findmnt` | [MEASURED] |' \
      '| Hostname | `imx95evk` — NOT UNIQUE; identify via `/proc/device-tree/model` | [MEASURED] |' ; do
        _run_one "$g"
        if [ "$FINDINGS" -eq 0 ]; then
            pass=$((pass + 1)); echo "  [PASS] quiet: $(printf '%s' "$g" | cut -c1-58)…"
        else
            fail=$((fail + 1)); echo "  [FAIL] false positive: $(printf '%s' "$g" | cut -c1-58)…"
        fi
    done

    echo "--- self-test: $pass passed, $fail failed"
    [ "$fail" -eq 0 ] || return 2
    return 0
}

case "${1:-}" in
    --self-test) self_test || exit 2; exit 0 ;;
    "") echo "usage: relation_lint.sh --self-test | <file.md> [file.md ...]" >&2; exit 3 ;;
esac

for f in "$@"; do lint_file "$f" || exit 3; done

if [ "$FINDINGS" -gt 0 ]; then
    echo
    echo "relation_lint: $FINDINGS finding(s) in FACT ROWS."
    echo "Each is a JOIN with no provenance: cite the artifact, or tag it [UNVERIFIED]."
    echo "See ground-truth §0 rule 2. NOTE: prose is not scanned, and an unstated"
    echo "premise (defect #2) is undetectable here — a clean run is not a clean document."
    exit 1
fi
echo "relation_lint: no findings in fact rows."
echo "  Scope: table rows only. Prose is NOT scanned; unstated premises are NOT detectable."
exit 0
