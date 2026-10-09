#!/usr/bin/env bash
# evals/relation_lint.sh
#
# Partial mechanical enforcement of the SECOND provenance rule in
# references/imx95-ground-truth.md §0:
#
#     A RELATION NEEDS ITS OWN PROVENANCE.
#     "Name the artifact that establishes this JOIN."
#
# ─── WHAT THIS CATCHES: 3 OF THE 4 DEFECTS THAT MOTIVATED IT. NOT 4. ─────────
#
# Validated retrospectively against the four real 2026-10-08 defects, each line
# taken VERBATIM FROM GIT HISTORY (not paraphrased — see the note below):
#
#   #1  8bd1f17 L67   "| Storage | eMMC, 29.6 GB, ... |"              CAUGHT by R1
#   #2  3f7d646 L68   "67 G of mounted filesystem cannot sit on a
#                      29.6 GB device ... — see §5"                   ❌ NOT CAUGHT
#   #3  (pre-fix)     "eMMC 29.6 GB [SOURCED], microSD slot ..."      CAUGHT by R2
#   #4  23da184 L436  "...This is almost certainly why the `.ORIG`
#                      DTB backups were reported in two places."      CAUGHT by R3
#
# 🔴 WHY #2 IS OUT OF REACH, AND WHY THAT IS THE IMPORTANT PART.
# Defect #2's real text cites a device node (`/run/media/root-mmcblk0p2`) AND a
# document section (`§5`). Every rule here is discharged by it, correctly — the
# sentence was properly cited. The error was an UNSTATED PREMISE: that both
# mounts lived on one device. **No keyword lint can see a premise that was never
# written down.** #2 was the subtlest of the four and it is the one that needed a
# command (`lsblk`), not a checker.
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
# the 3 catchable historical defects AND that it stays silent on legitimate lines
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
_FILENAME_ROW='\.uuu|\.dts|\.dtsi|\.dtb|\.bin|\.wic|\.sdcard'
# NOTE the tags are matched WITHOUT a closing bracket. The first version required
# `\[UNVERIFIED\]` exactly, so a tag that carried its reason — `[UNVERIFIED: no
# 15x15 board in the fleet]`, which is the better way to write it — failed to
# discharge the rule and the lint kept firing on a correctly-tagged row. A
# checker that only accepts the terse form of a tag pushes authors toward the
# less informative one.
_NODE_CITED='mmcblk[0-9]|mmc[0-9]|/dev/root|nvme[0-9]|findmnt|lsblk|\[UNKNOWN|\[UNVERIFIED'

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
    local f="$1" n=0 line
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

        if printf '%s' "$line" | grep -qiE "$_AMBIGUOUS_NOUN" \
           && ! printf '%s' "$line" | grep -qE "$_NODE_CITED" \
           && ! printf '%s' "$line" | grep -qiE "$_FILENAME_ROW"; then
            _report "$f" "$n" R1 \
              'hardware noun with >1 possible referent and no device node' "$line"
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

    echo "--- (a) must FLAG the 3 catchable historical defects"
    for spec in "1:$d1" "3:$d3" "4:$d4"; do
        _run_one "${spec#*:}"
        if [ "$FINDINGS" -gt 0 ]; then
            echo "  [PASS] defect #${spec%%:*} flagged"; pass=$((pass + 1))
        else
            echo "  [FAIL] defect #${spec%%:*} SLIPPED — do not ship"; fail=$((fail + 1))
        fi
    done

    # (b) The KNOWN-UNCATCHABLE one. Asserting this stays quiet keeps the
    #     limitation honest: if a future edit makes it fire, the header's
    #     "3 of 4" claim is stale and must be updated.
    echo "--- (b) defect #2 is KNOWN out of reach (unstated premise) — assert it stays quiet"
    _run_one '| ⚠️ Storage size | ~~eMMC 29.6 GB~~ — **CONTRADICTED, do not use.** `/` alone measures **56 G** and `/run/media/root-mmcblk0p2` **11 G**: 67 G of mounted filesystem cannot sit on a 29.6 GB device. True capacity, and which device backs `/`, are open — see §5. | [UNVERIFIED] |'
    if [ "$FINDINGS" -eq 0 ]; then
        echo "  [PASS] #2 quiet, as documented (it cited a node AND §5; the error was a premise)"
        pass=$((pass + 1))
    else
        echo "  [FAIL] #2 now fires — GOOD news, but the header says 3-of-4 and is now WRONG. Update it."
        fail=$((fail + 1))
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

    echo "--- (c) must stay SILENT on legitimate fact rows"
    local g
    for g in \
      '| eMMC `mmcblk0` capacity | **29.6 GB** (62160896 sectors, from `/sys/block`) | [MEASURED] |' \
      '| SD bus configuration | **SDR104, 4-bit** — from `/sys/kernel/debug/mmc1/ios` | [SOURCED — kernel driver] |' \
      '| Live boot partition | `/run/media/boot-mmcblk1p1` — both `.ORIG` copies are there and in `/root`, per dossier §2 | [SOURCED] |' \
      '| …its form factor | **[UNKNOWN]** — neither field says micro- vs full-size | [UNKNOWN] |' \
      '| Rootfs device | `/dev/mmcblk1p2` via `findmnt` | [MEASURED] |' ; do
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
