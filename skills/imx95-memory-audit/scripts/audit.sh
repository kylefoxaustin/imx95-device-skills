#!/bin/bash
# skills/imx95-memory-audit/scripts/audit.sh
#
# Detailed memory audit for i.MX 95.
# Sections: MEMINFO, CMA, DMA-BUF, PROCESSES (top-10 RSS),
#           HUGEPAGES, VMALLOC, SLAB
#
# Usage: audit.sh [--summary] [--section NAME] [-h]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/sysfs.sh
source "${REPO_ROOT}/lib/sysfs.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --summary         Print one-line summary only
  --section NAME    Run only this section (MEMINFO CMA DMABUF PROCESSES
                    HUGEPAGES VMALLOC SLAB)
  -h, --help        Show this help
EOF
}

SUMMARY_ONLY=0
SECTIONS_FILTER=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --summary)   SUMMARY_ONLY=1; shift ;;
        --section)   SECTIONS_FILTER+=("${2^^}"); shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

should_run() {
    local s="${1^^}"
    [ "${#SECTIONS_FILTER[@]}" -eq 0 ] && return 0
    for f in "${SECTIONS_FILTER[@]}"; do [ "${f}" = "${s}" ] && return 0; done
    return 1
}

section_header() { echo ""; echo "=== $1 ==="; }

# Mount debugfs if needed (non-destructive)
ensure_debugfs_mounted

# ---------------------------------------------------------------------------
# SECTION: MEMINFO SUMMARY
# ---------------------------------------------------------------------------
if should_run "MEMINFO"; then
    section_header "MEMINFO SUMMARY"

    eval "$(awk '
        /^MemTotal:/     {printf "MT=%s\n",  $2}
        /^MemFree:/      {printf "MF=%s\n",  $2}
        /^MemAvailable:/ {printf "MA=%s\n",  $2}
        /^Cached:/       {printf "MC=%s\n",  $2}
        /^Buffers:/      {printf "MB=%s\n",  $2}
        /^SwapTotal:/    {printf "ST=%s\n",  $2}
        /^SwapFree:/     {printf "SF=%s\n",  $2}
        /^CmaTotal:/     {printf "CT=%s\n",  $2}
        /^CmaFree:/      {printf "CF=%s\n",  $2}
        /^VmallocUsed:/  {printf "VU=%s\n",  $2}
        /^VmallocTotal:/ {printf "VT=%s\n",  $2}
        /^Shmem:/        {printf "SH=%s\n",  $2}
        /^AnonPages:/    {printf "AP=%s\n",  $2}
        /^Mapped:/       {printf "MP=%s\n",  $2}
    ' /proc/meminfo 2>/dev/null)"

    to_mb() { echo $(( ${1:-0} / 1024 )); }
    pct()   { local t="${1:-0}"; local u="${2:-0}"; [ "${t}" -gt 0 ] && echo "$(( u * 100 / t ))" || echo "0"; }

    MT_MB=$(to_mb "${MT:-0}"); MA_MB=$(to_mb "${MA:-0}"); MF_MB=$(to_mb "${MF:-0}")
    MC_MB=$(to_mb "${MC:-0}"); MB_MB=$(to_mb "${MB:-0}"); ST_MB=$(to_mb "${ST:-0}")
    SF_MB=$(to_mb "${SF:-0}"); CT_MB=$(to_mb "${CT:-0}"); CF_MB=$(to_mb "${CF:-0}")
    VU_MB=$(to_mb "${VU:-0}"); VT_MB=$(to_mb "${VT:-0}"); SH_MB=$(to_mb "${SH:-0}")
    AP_MB=$(to_mb "${AP:-0}"); MP_MB=$(to_mb "${MP:-0}")

    USED_MB=$(( MT_MB - MA_MB ))
    USED_PCT=$(pct "${MT_MB}" "${USED_MB}")
    CMA_USED_MB=$(( CT_MB - CF_MB ))
    CMA_USED_PCT=$(pct "${CT_MB}" "${CMA_USED_MB}")

    printf "%-18s: %d MB\n"                    "Total RAM"    "${MT_MB}"
    printf "%-18s: %d MB  (%d%% used)\n"       "Available"    "${MA_MB}" "${USED_PCT}"
    printf "%-18s: %d MB\n"                    "Free (raw)"   "${MF_MB}"
    printf "%-18s: %d MB\n"                    "Page cache"   "${MC_MB}"
    printf "%-18s: %d MB\n"                    "Buffers"      "${MB_MB}"
    printf "%-18s: %d MB\n"                    "Anonymous"    "${AP_MB}"
    printf "%-18s: %d MB\n"                    "Mapped"       "${MP_MB}"
    printf "%-18s: %d MB\n"                    "Shared (shmem)" "${SH_MB}"
    printf "%-18s: %d MB total, %d MB free  (%d%% used)\n" \
        "CMA"          "${CT_MB}" "${CF_MB}" "${CMA_USED_PCT}"
    printf "%-18s: %d MB total, %d MB free\n"  "Swap"         "${ST_MB}" "${SF_MB}"
    printf "%-18s: %d MB used / %d MB total\n" "Vmalloc"      "${VU_MB}" "${VT_MB}"

    echo ""
    # Assessment
    if   [ "${MA_MB}" -lt 128 ]; then
        echo "STATUS: CRITICAL — ${MA_MB} MB available. OOM kills imminent."
    elif [ "${MA_MB}" -lt 256 ]; then
        echo "STATUS: HIGH PRESSURE — ${MA_MB} MB available."
    elif [ "${CMA_USED_PCT}" -gt 80 ]; then
        echo "STATUS: CMA PRESSURE — CMA is ${CMA_USED_PCT}% used (${CMA_USED_MB}/${CT_MB} MB)."
    else
        echo "STATUS: ${MA_MB} MB available. ⚠️ CMA health NOT ASSESSED — see below."
    fi

    # ───────────────────────────────────────────────────────────────────────
    # 🔴 WHY THIS NO LONGER SAYS "CMA n% used" AS IF THAT MEANT ANYTHING.
    #
    # On the neutron DTB, /proc/meminfo CmaFree is the SUM OF TWO POOLS:
    #     linux,cma         960 MiB   <- the pool the TFLite delegate draws from
    #     neutron_memory   4096 MiB   <- the ONNX/LLM EP's dedicated pool
    #     CmaTotal        ~5056 MiB
    # This kernel has no CONFIG_CMA_DEBUGFS, so THERE IS NO PER-POOL ACCOUNTING.
    #
    # The arithmetic that makes the old threshold useless: if the ENTIRE 960 MiB
    # linux,cma pool is exhausted — the exact condition that makes the Neutron
    # delegate fail with "Neutron hardware init failed!!!" and silently run the
    # whole graph on the A55s — the aggregate reads
    #     960 / 5056 = 19.0% used
    # which is BELOW the 80% CMA-PRESSURE threshold. So this script printed
    # "STATUS: OK" at the precise moment the delegate could not allocate.
    #
    # ⇒ An aggregate that cannot distinguish the pool that matters must not be
    #   reported as a health verdict. It is printed as a raw number with its
    #   composition stated, and the verdict is withheld. Refuse, do not degrade.
    echo ""
    echo "CMA: ${CF_MB} MB free of ${CT_MB} MB total — ⚠️ AGGREGATE OF TWO POOLS, NOT A HEALTH SIGNAL"
    if [ "${CT_MB}" -gt 4000 ]; then
        echo "  CmaTotal > 4 GiB ⇒ the neutron DTB is booted, so this figure sums"
        echo "  linux,cma (~960 MiB, used by the TFLite delegate) + neutron_memory (~4096 MiB)."
        echo "  No CONFIG_CMA_DEBUGFS on this kernel ⇒ no per-pool accounting exists."
        echo "  ⇒ A healthy-looking total does NOT prove the delegate's 960 MiB pool is free."
        echo "  ⇒ Full exhaustion of that pool reads as only ~19% of the aggregate, which is"
        echo "     why no percentage threshold here can detect the CMA trap."
        echo "  To prove an offload actually happened, watch CmaFree DURING a run and gate on"
        echo "  the placement line — see lib/neutron.sh and ground-truth §2.2."
    fi

    if [ "${SUMMARY_ONLY}" = "1" ]; then exit 0; fi
fi

# ---------------------------------------------------------------------------
# SECTION: CMA REGIONS
# ---------------------------------------------------------------------------
if should_run "CMA"; then
    section_header "CMA REGIONS"

    CMA_DEBUG_DIR="/sys/kernel/debug/cma"
    if [ -d "${CMA_DEBUG_DIR}" ]; then
        printf "%-24s %-12s %-12s %-12s %-8s\n" "Region" "Total" "Used" "Free" "Used%"
        printf "%-24s %-12s %-12s %-12s %-8s\n" "------" "-----" "----" "----" "-----"

        for region_dir in "${CMA_DEBUG_DIR}"/*/; do
            [ -d "${region_dir}" ] || continue
            region_name=$(basename "${region_dir}")

            # count = total pages, used = used pages
            count=$(sysfs_read "${region_dir}count" "0")
            used=$(sysfs_read "${region_dir}used" "0")

            # Page size is typically 4096 bytes on ARM64
            PAGE_SIZE=4096
            total_mb=$(( count * PAGE_SIZE / 1024 / 1024 ))
            used_mb=$(( used  * PAGE_SIZE / 1024 / 1024 ))
            free_mb=$(( total_mb - used_mb ))
            used_pct=0
            [ "${total_mb}" -gt 0 ] && used_pct=$(( used_mb * 100 / total_mb ))

            flag=""
            [ "${used_pct}" -ge 80 ] && flag=" *** HIGH"
            [ "${used_pct}" -ge 95 ] && flag=" *** CRITICAL"

            printf "%-24s %-12s %-12s %-12s %-8s%s\n" \
                "${region_name}" "${total_mb} MB" "${used_mb} MB" "${free_mb} MB" \
                "${used_pct}%" "${flag}"
        done
    else
        echo "Per-region CMA debugfs not available (CONFIG_CMA_DEBUGFS may not be set)."
        echo "Showing aggregate from /proc/meminfo:"
        CT=$(awk '/^CmaTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo "0")
        CF=$(awk '/^CmaFree:/{print $2}'  /proc/meminfo 2>/dev/null || echo "0")
        CU=$(( CT - CF ))
        printf "  CMA Total : %d MB\n" "$(( CT / 1024 ))"
        printf "  CMA Used  : %d MB\n" "$(( CU / 1024 ))"
        printf "  CMA Free  : %d MB\n" "$(( CF / 1024 ))"
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: DMA-BUF
# ---------------------------------------------------------------------------
if should_run "DMABUF"; then
    section_header "DMA-BUF"

    BUFINFO="/sys/kernel/debug/dma_buf/bufinfo"
    if [ -f "${BUFINFO}" ]; then
        # Parse bufinfo: each buffer has size, exporter name
        TOTAL_BYTES=0
        BUF_COUNT=0

        echo "DMA-BUF buffer inventory:"
        printf "  %-12s %-30s %s\n" "Size" "Exporter" "Name"
        printf "  %-12s %-30s %s\n" "----" "--------" "----"

        while IFS= read -r line; do
            # Lines look like: "size: 4194304  flags: 0x2  mode: 0x1  name: camera-buf  exp_name: imx-media"
            if echo "${line}" | grep -q "^size:"; then
                sz=$(echo "${line}" | grep -oP 'size:\s*\K[0-9]+' || echo "0")
                exp=$(echo "${line}" | grep -oP 'exp_name:\s*\K\S+' || echo "unknown")
                nm=$(echo "${line}"  | grep -oP 'name:\s*\K\S+' || echo "")
                sz_mb=$(( sz / 1024 / 1024 ))
                printf "  %-12s %-30s %s\n" "${sz_mb} MB" "${exp}" "${nm}"
                TOTAL_BYTES=$(( TOTAL_BYTES + sz ))
                BUF_COUNT=$(( BUF_COUNT + 1 ))
            fi
        done < "${BUFINFO}"

        echo ""
        printf "  Total DMA-BUF: %d buffers, %d MB\n" "${BUF_COUNT}" "$(( TOTAL_BYTES / 1024 / 1024 ))"
    else
        echo "DMA-BUF bufinfo not available."
        echo "  Ensure debugfs is mounted: mount -t debugfs none /sys/kernel/debug"
        echo "  And kernel has CONFIG_DMA_BUF_SYSFS_STATS=y"
    fi

    # Also check /proc/*/fdinfo for DMA-BUF fds (requires root)
    if [ "$(id -u)" -eq 0 ]; then
        echo ""
        echo "Per-process DMA-BUF usage (from /proc/*/fdinfo):"
        declare -A proc_dmabuf_mb
        for fdinfo_dir in /proc/[0-9]*/fdinfo/; do
            [ -d "${fdinfo_dir}" ] || continue
            pid=$(echo "${fdinfo_dir}" | grep -oP '/proc/\K[0-9]+')
            total_size=0
            for fdinfo in "${fdinfo_dir}"*; do
                [ -f "${fdinfo}" ] || continue
                if grep -q "^dmabuf" "${fdinfo}" 2>/dev/null; then
                    sz=$(grep "^size:" "${fdinfo}" 2>/dev/null | awk '{print $2}' || echo "0")
                    total_size=$(( total_size + sz ))
                fi
            done
            if [ "${total_size}" -gt 0 ]; then
                comm=$(cat "/proc/${pid}/comm" 2>/dev/null || echo "pid${pid}")
                proc_dmabuf_mb["${comm}"]=$(( (${proc_dmabuf_mb["${comm}"]:-0}) + total_size / 1024 / 1024 ))
            fi
        done

        if [ "${#proc_dmabuf_mb[@]}" -gt 0 ]; then
            for proc in "${!proc_dmabuf_mb[@]}"; do
                printf "  %-30s %d MB\n" "${proc}" "${proc_dmabuf_mb[${proc}]}"
            done | sort -k2 -rn | head -10
        else
            echo "  No per-process DMA-BUF usage found (or no DMA-BUF fds open)."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: TOP PROCESSES BY RSS
# ---------------------------------------------------------------------------
if should_run "PROCESSES"; then
    section_header "TOP PROCESSES BY RSS"

    echo "Top 10 processes by Resident Set Size (RSS):"
    printf "  %-8s %-30s %-12s %-12s\n" "PID" "Name" "RSS" "VmSize"
    printf "  %-8s %-30s %-12s %-12s\n" "---" "----" "---" "------"

    # Collect RSS from /proc/*/status
    declare -a rss_entries=()
    for status_file in /proc/[0-9]*/status; do
        [ -f "${status_file}" ] || continue
        pid=$(echo "${status_file}" | grep -oP '/proc/\K[0-9]+')

        name=$(grep "^Name:" "${status_file}" 2>/dev/null | awk '{print $2}' || echo "unknown")
        rss_kb=$(grep "^VmRSS:" "${status_file}" 2>/dev/null | awk '{print $2}' || echo "0")
        vsz_kb=$(grep "^VmSize:" "${status_file}" 2>/dev/null | awk '{print $2}' || echo "0")

        [ "${rss_kb}" -gt 0 ] 2>/dev/null || continue
        rss_entries+=("${rss_kb} ${pid} ${name} ${vsz_kb}")
    done

    # Sort by RSS descending, show top 10
    printf '%s\n' "${rss_entries[@]}" 2>/dev/null | sort -rn | head -10 | \
    while read -r rss_kb pid name vsz_kb; do
        rss_mb=$(( rss_kb / 1024 ))
        vsz_mb=$(( vsz_kb / 1024 ))
        printf "  %-8s %-30s %-12s %-12s\n" \
            "${pid}" "${name}" "${rss_mb} MB" "${vsz_mb} MB"
    done
fi

# ---------------------------------------------------------------------------
# SECTION: HUGEPAGES
# ---------------------------------------------------------------------------
if should_run "HUGEPAGES"; then
    section_header "HUGEPAGES"

    HP_TOTAL=$(sysfs_read "/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages" "0")
    HP_FREE=$(sysfs_read  "/sys/kernel/mm/hugepages/hugepages-2048kB/free_hugepages" "0")
    HP_RSVD=$(sysfs_read  "/sys/kernel/mm/hugepages/hugepages-2048kB/resv_hugepages" "0")

    if [ "${HP_TOTAL}" -gt 0 ]; then
        printf "  %-20s: %s\n" "2MB hugepages total"  "${HP_TOTAL}"
        printf "  %-20s: %s\n" "2MB hugepages free"   "${HP_FREE}"
        printf "  %-20s: %s\n" "2MB hugepages rsvd"   "${HP_RSVD}"
    else
        echo "  Hugepages: not configured (nr_hugepages=0)"
        echo "  Note: i.MX 95 workloads typically do not require hugepages."
    fi

    # Transparent hugepages
    THP_ENABLED=$(sysfs_read "/sys/kernel/mm/transparent_hugepage/enabled" "unknown")
    printf "  %-20s: %s\n" "THP enabled" "${THP_ENABLED}"
fi

# ---------------------------------------------------------------------------
# SECTION: VMALLOC
# ---------------------------------------------------------------------------
if should_run "VMALLOC"; then
    section_header "VMALLOC"

    VU=$(awk '/^VmallocUsed:/{print $2}' /proc/meminfo 2>/dev/null || echo "0")
    VT=$(awk '/^VmallocTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo "0")
    VC=$(awk '/^VmallocChunk:/{print $2}' /proc/meminfo 2>/dev/null || echo "0")

    printf "  %-20s: %d MB\n" "VmallocTotal"  "$(( VT / 1024 ))"
    printf "  %-20s: %d MB\n" "VmallocUsed"   "$(( VU / 1024 ))"
    printf "  %-20s: %d MB\n" "VmallocChunk"  "$(( VC / 1024 ))"

    # Check /proc/vmallocinfo for large allocations (requires root)
    if [ -r "/proc/vmallocinfo" ]; then
        echo ""
        echo "  Largest vmalloc allocations:"
        awk '{print $2, $NF}' /proc/vmallocinfo 2>/dev/null | \
            sort -rn | head -5 | \
            awk '{printf "    %8d KB  %s\n", $1/1024, $2}'
    fi
fi

# ---------------------------------------------------------------------------
# SECTION: SLAB TOP CONSUMERS
# ---------------------------------------------------------------------------
if should_run "SLAB"; then
    section_header "SLAB TOP CONSUMERS"

    if [ -r "/proc/slabinfo" ]; then
        echo "Top 10 slab caches by total memory:"
        printf "  %-32s %-12s %-12s %-12s\n" "Cache" "Obj Size" "Num Objs" "Total"
        printf "  %-32s %-12s %-12s %-12s\n" "-----" "--------" "--------" "-----"

        # slabinfo format: name num_active_objs total_objs obj_size ...
        awk 'NR>2 {
            name=$1; total_objs=$3; obj_size=$4
            total_bytes = total_objs * obj_size
            printf "%d %s %d %d\n", total_bytes, name, obj_size, total_objs
        }' /proc/slabinfo 2>/dev/null | sort -rn | head -10 | \
        while read -r total_bytes name obj_size total_objs; do
            total_mb=$(( total_bytes / 1024 / 1024 ))
            printf "  %-32s %-12s %-12s %-12s\n" \
                "${name}" "${obj_size} B" "${total_objs}" "${total_mb} MB"
        done
    else
        echo "  /proc/slabinfo not readable (requires root)."
        echo "  Run as root for slab statistics."
    fi
fi

echo ""
echo "Memory audit complete. Timestamp: $(timestamp)"
