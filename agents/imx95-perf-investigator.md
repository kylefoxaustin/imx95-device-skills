---
name: imx95-perf-investigator
version: "0.1.0"
platform: imx95
type: agent
invoke_when:
  - "the board feels slow"
  - "performance is degraded"
  - "investigate performance"
  - "why is my application slow"
  - "CPU is throttling"
  - "NPU is slow"
  - "latency is high"
  - "benchmark results are worse than expected"
  - "something is wrong with performance"
depends_on:
  - imx95-diagnostic
  - imx95-memory-audit
safe: true
destructive: false
---

# Agent: imx95-perf-investigator

## Purpose

This agent guides Claude through a structured, end-to-end performance investigation on the
FRDM-IMX95 EVK. When a user reports that the board "feels slow", a workload is underperforming,
or benchmark results are unexpectedly low, Claude follows this procedure to systematically
identify the root cause and produce an actionable report.

The investigation covers seven areas in order of likelihood and ease of detection:
thermal throttling → CPU/GPU/NPU frequency scaling → memory pressure → IRQ storms →
kernel errors → process-level analysis → synthesis.

**Do not skip steps.** Each step's output informs the next. Record all findings as you go —
the final report template at the end of this document requires data from every step.

---

## Pre-Flight Checklist

Before starting the investigation, confirm:

1. You are connected to the correct board — **verify with `cat /proc/device-tree/model`, which must
   read `NXP FRDM-IMX95-PRO`. NOT with `hostname`:** two physically different boards in the fleet
   answer to `imx95evk`, and the wrong one returns perfectly self-consistent readings with no error
   to notice. A whole investigation can complete against the wrong board and look clean.
   `uname -r` is worth checking too, but **model is the identity**.
2. The user has described the symptom: which workload is slow, since when, and any recent
   changes (BSP update, new application, changed governor, etc.).
3. The workload is either currently running or can be reproduced on demand.
4. You have root access (required for some `/proc` and debugfs reads).

If the workload cannot be reproduced, run the investigation in "idle baseline" mode and note
that findings reflect idle state, not loaded state.

---

## Investigation Procedure

### Step 1 — Capture Diagnostic Snapshot

**Skill:** `imx95-diagnostic`
**Script:** `skills/imx95-diagnostic/scripts/snapshot.sh`
**Purpose:** Establish a complete baseline of board state before deeper analysis.

```bash
bash skills/imx95-diagnostic/scripts/snapshot.sh 2>&1 | tee /tmp/perf_snapshot.txt
```

**What to record from output:**
- Board model, SoC revision, kernel version, uptime
- CPU governor for all 6 cores (expected: `schedutil` or `performance`)
- Current CPU frequencies for all cores (expected: up to 1800 MHz under load)
- All thermal zone temperatures (flag any zone ≥ 75°C)
- Available memory (flag if < 256 MB available)
- Any `[ERROR]` or `[WARN]` lines in dmesg section

**Decision gate:**
- If dmesg shows kernel panics, OOM kills, or hardware errors → **jump to Step 6** first,
  then return here.
- If all CPUs are at minimum frequency (300 MHz) at idle → note as expected, not a problem.
- If all CPUs are at minimum frequency **under load** → thermal throttling or governor issue;
  **Step 2 is critical**.

---

### Step 2 — Check Thermal Throttling

**Purpose:** Thermal throttling is the most common cause of sustained performance degradation
on i.MX 95. The SoC begins passive cooling at ~85°C and hard-throttles at ~95°C.

**Commands to run:**

```bash
# Read all thermal zones with labels
for zone in /sys/class/thermal/thermal_zone*/; do
    type=$(cat "${zone}type" 2>/dev/null || echo "unknown")
    temp=$(cat "${zone}temp" 2>/dev/null || echo "0")
    temp_c=$(( temp / 1000 ))
    echo "  ${type}: ${temp_c}°C"
done

# Check for throttle events (cooling device state > 0 means active cooling)
for cdev in /sys/class/thermal/cooling_device*/; do
    name=$(cat "${cdev}type" 2>/dev/null || echo "unknown")
    state=$(cat "${cdev}cur_state" 2>/dev/null || echo "0")
    max=$(cat "${cdev}max_state" 2>/dev/null || echo "0")
    if [ "${state}" -gt 0 ]; then
        echo "  ACTIVE COOLING: ${name} state=${state}/${max}"
    fi
done

# Check trip points for CPU thermal zone
CPU_ZONE=$(grep -rl "cpu-thermal\|cpu0-thermal\|A55" /sys/class/thermal/thermal_zone*/type 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -n "${CPU_ZONE}" ]; then
    echo "CPU thermal zone: ${CPU_ZONE}"
    for trip in "${CPU_ZONE}"/trip_point_*_temp; do
        [ -f "${trip}" ] || continue
        trip_name=$(basename "${trip}" _temp)
        trip_type_file="${CPU_ZONE}/${trip_name}_type"
        trip_type=$(cat "${trip_type_file}" 2>/dev/null || echo "unknown")
        trip_temp=$(cat "${trip}" 2>/dev/null || echo "0")
        echo "  ${trip_name} (${trip_type}): $(( trip_temp / 1000 ))°C"
    done
fi
```

**Interpretation:**

| CPU Temp | Assessment | Action |
|----------|------------|--------|
| < 70°C | Normal | Thermal is not the cause |
| 70–84°C | Warm | Monitor; may throttle under sustained load |
| 85–94°C | Throttling | Passive cooling active; CPU freq will be capped |
| ≥ 95°C | Hard throttle | Immediate frequency reduction; check airflow/heatsink |

**If throttling is confirmed:**
- Check if a heatsink is attached to the SoC.
- Check ambient temperature.
- Suggest: reduce workload concurrency, add cooling, or set a lower performance target.
- Note: on FRDM-IMX95 EVK, the board has a small heatsink; sustained NPU + CPU workloads
  can push temps above 85°C within 2–3 minutes.

**Record:** Max temperature observed, whether any cooling device is active, trip point margins.

---

### Step 3 — Check CPU / GPU / NPU Frequency Scaling

**Purpose:** Verify that frequency governors are set correctly and that the hardware is
actually running at the expected frequencies.

#### 3a — CPU Frequency (all 6 Cortex-A55 cores)

```bash
echo "=== CPU Frequency Status ==="
for cpu in /sys/devices/system/cpu/cpu[0-5]/; do
    cpu_id=$(basename "${cpu}")
    online=$(cat "${cpu}online" 2>/dev/null || echo "1")
    if [ "${online}" = "0" ]; then
        echo "  ${cpu_id}: OFFLINE"
        continue
    fi
    freq_file="${cpu}cpufreq/scaling_cur_freq"
    gov_file="${cpu}cpufreq/scaling_governor"
    min_file="${cpu}cpufreq/scaling_min_freq"
    max_file="${cpu}cpufreq/scaling_max_freq"
    cur_khz=$(cat "${freq_file}" 2>/dev/null || echo "0")
    gov=$(cat "${gov_file}" 2>/dev/null || echo "unknown")
    min_khz=$(cat "${min_file}" 2>/dev/null || echo "0")
    max_khz=$(cat "${max_file}" 2>/dev/null || echo "0")
    echo "  ${cpu_id}: $(( cur_khz / 1000 )) MHz  governor=${gov}  range=$(( min_khz/1000 ))–$(( max_khz/1000 )) MHz"
done

# Show available governors
echo ""
echo "Available governors: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null)"
echo "Available frequencies: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null | tr ' ' '\n' | awk '{printf "%d MHz\n", $1/1000}' | tr '\n' ', ')"
```

**Expected under load:** All online cores at or near 1800 MHz with `schedutil` or `performance` governor.

**Red flags:**
- Governor is `powersave` → all cores locked to minimum frequency. Fix: `echo schedutil > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`
- `scaling_max_freq` is set below 1800000 → someone has capped the frequency. Check `/etc/rc.local` or systemd services.
- Cores 4–5 offline → check `echo 1 > /sys/devices/system/cpu/cpu4/online`

#### 3b — GPU Frequency (Arm Mali-G310 — graphics only, NOT an ML backend)

```bash
echo "=== GPU Frequency Status ==="
GPU_DEVFREQ=""
# Search for GPU devfreq node
for dev in /sys/class/devfreq/*/; do
    name=$(cat "${dev}device/uevent" 2>/dev/null | grep DRIVER | head -1 || basename "${dev}")
    if echo "${name}" | grep -qi "mali\|gpu\|gc\|vivante\|galcore"; then
        GPU_DEVFREQ="${dev}"
        break
    fi
done
# Also try known path
[ -z "${GPU_DEVFREQ}" ] && GPU_DEVFREQ=$(ls -d /sys/class/devfreq/*gpu* 2>/dev/null | head -1)
[ -z "${GPU_DEVFREQ}" ] && GPU_DEVFREQ=$(ls -d /sys/class/devfreq/*gc* 2>/dev/null | head -1)

if [ -n "${GPU_DEVFREQ}" ]; then
    cur=$(cat "${GPU_DEVFREQ}cur_freq" 2>/dev/null || echo "0")
    min=$(cat "${GPU_DEVFREQ}min_freq" 2>/dev/null || echo "0")
    max=$(cat "${GPU_DEVFREQ}max_freq" 2>/dev/null || echo "0")
    gov=$(cat "${GPU_DEVFREQ}governor" 2>/dev/null || echo "unknown")
    echo "  GPU: $(( cur / 1000000 )) MHz  governor=${gov}  range=$(( min/1000000 ))–$(( max/1000000 )) MHz"
else
    echo "  GPU devfreq node not found — GPU may be idle or driver not loaded"
fi
```

#### 3c — NPU State

> ⚠️ **`ethosu` is not this SoC's NPU.** An earlier version of this block searched for
> `ethosu` drivers and `libethosu_delegate.so` / `libvx_delegate.so`. Those belong to the
> **i.MX93** and **i.MX8M Plus**. On i.MX95 the driver is `neutron` and the delegate is
> `libneutron_delegate.so`. See `references/imx95-ground-truth.md` §1.1.

```bash
echo "=== NPU / eIQ Neutron State ==="
NPU_FOUND=0
for path in /sys/bus/platform/drivers/neutron* /sys/bus/platform/drivers/imx-neutron*; do
    if [ -d "${path}" ]; then
        echo "  Neutron driver: $(basename ${path}) — bound"
        NPU_FOUND=1
    fi
done

for mod in neutron imx_neutron; do
    lsmod 2>/dev/null | grep -q "^${mod}" && { echo "  Kernel module '${mod}': loaded"; NPU_FOUND=1; }
done

[ -e /dev/neutron0 ] && { echo "  /dev/neutron0: present"; NPU_FOUND=1; }
[ "${NPU_FOUND}" = "0" ] && echo "  Neutron NOT detected — no NPU number from this board is valid"

# TFLite stack
for lib in /usr/lib/libneutron_delegate.so /usr/lib/liblitert_neutron_delegate.so; do
    [ -f "${lib}" ] && echo "  Neutron delegate: ${lib}"
done
# ONNX Runtime EP — a SEPARATE stack with its own placement signal
for lib in /usr/lib/libonnxruntime.so.1.24.3 /usr/lib/libNeutronDriver.so; do
    [ -f "${lib}" ] && echo "  ORT Neutron EP: ${lib}"
done
# Wrong-SoC delegates: report, never use
for lib in /usr/lib/libethosu_delegate.so /usr/lib/libvx_delegate.so; do
    [ -f "${lib}" ] && echo "  ⚠️ WRONG-SoC delegate present: ${lib} — never load on i.MX95"
done

# The SECOND NPU. Presence only — occupancy is host-undetectable (ground-truth §3.1).
lspci -nn 2>/dev/null | grep -i '1e58:0002' && echo "  ARA240 (Kinara M.2): enumerated" \
    || echo "  ARA240: not enumerated"
```

**Record:** CPU governor, per-core frequencies, GPU frequency, Neutron driver + delegate state,
ARA240 presence.

> ⚠️ **`/dev/neutron0` presence is not availability, and the ARA240's occupancy cannot be
> determined from the host at all.** Do not report either accelerator as "free".

---

### Step 4 — Check Memory Pressure

**Skill:** `imx95-memory-audit`
**Script:** `skills/imx95-memory-audit/scripts/audit.sh`

```bash
bash skills/imx95-memory-audit/scripts/audit.sh 2>&1 | tee /tmp/perf_memory.txt
```

**Key metrics to extract:**

```bash
# Quick memory pressure check
awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} /CmaTotal/{ct=$2} /CmaFree/{cf=$2}
     END {
       used_pct = int((t-a)*100/t)
       cma_used_pct = (ct>0) ? int((ct-cf)*100/ct) : 0
       printf "RAM: %d MB total, %d MB available (%d%% used)\n", t/1024, a/1024, used_pct
       printf "CMA: %d MB total, %d MB free (%d%% used)\n", ct/1024, cf/1024, cma_used_pct
     }' /proc/meminfo

# Check for OOM events
dmesg --notime 2>/dev/null | grep -i "out of memory\|oom.kill\|killed process" | tail -5
```

**Interpretation:**

| Available RAM | Assessment |
|---------------|------------|
| > 512 MB | Healthy |
| 256–512 MB | Moderate pressure |
| 128–256 MB | High pressure — may cause swapping or allocation failures |
| < 128 MB | Critical — OOM kills likely |

**CMA pressure** affects VPU, ISP, and NPU buffer allocation. If CMA is > 80% used and the
user is running camera or NPU workloads, this is likely the bottleneck.

**Record:** Available RAM %, CMA usage %, top-3 memory consumers, any OOM events.

---

### Step 5 — Check for IRQ Storms

**Purpose:** A runaway interrupt source can consume significant CPU time, causing all other
workloads to appear slow. This is especially common with misconfigured Ethernet, USB, or
camera drivers.

```bash
echo "=== IRQ Analysis ==="

# Capture two snapshots 2 seconds apart and compute delta
cp /proc/interrupts /tmp/irq_before.txt
sleep 2
cp /proc/interrupts /tmp/irq_after.txt

# Compute per-IRQ rate (interrupts per second)
echo "Top IRQ sources by rate (interrupts/sec over 2s sample):"
paste /tmp/irq_before.txt /tmp/irq_after.txt | \
awk '
NR==1 { next }  # skip header
{
    # Fields: IRQ_num, cpu0_before, ..., cpuN_before, type, name, IRQ_num2, cpu0_after, ...
    # This is a simplified approach — sum all CPU columns
    n = NF/2
    before = 0; after = 0
    for (i=2; i<=n; i++) before += $i
    for (i=n+2; i<=NF-2; i++) after += $i
    delta = after - before
    name = $NF
    if (delta > 100) printf "  %8d/s  IRQ%-5s  %s\n", delta/2, $1, name
}' | sort -rn | head -20

# Check softirq load
echo ""
echo "SoftIRQ totals:"
grep -E "NET_RX|NET_TX|BLOCK|TASKLET|SCHED|RCU" /proc/softirqs 2>/dev/null | \
awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; printf "  %-12s %d\n", $1, sum}' | sort -k2 -rn | head -10
```

**Red flags:**
- Any IRQ firing > 10,000/sec at idle → likely a driver bug or misconfigured polling.
- `NET_RX` softirq very high → network driver in polling mode or packet storm.
- `SCHED` softirq very high → scheduler overhead from too many threads.

**Record:** Top-3 IRQ sources by rate, any IRQ > 5000/sec.

---

### Step 6 — Check dmesg for Errors

**Purpose:** Kernel error messages often directly identify the root cause of performance
problems (e.g., DMA errors, clock failures, regulator warnings, remoteproc crashes).

```bash
echo "=== Kernel Messages (errors and warnings) ==="

# Errors (highest priority)
echo "--- ERRORS ---"
dmesg --notime --level=err 2>/dev/null | tail -30

# Warnings
echo "--- WARNINGS ---"
dmesg --notime --level=warn 2>/dev/null | tail -20

# Performance-relevant patterns
echo "--- PERFORMANCE PATTERNS ---"
dmesg --notime 2>/dev/null | grep -iE \
    "throttl|thermal|freq|clk|regulator|voltage|opp|devfreq|cpufreq|oom|memory|dma.error|timeout|hung|stall|watchdog" \
    | grep -v "^$" | tail -30

# Remoteproc state (M7/M33 crashes affect system performance)
echo "--- REMOTEPROC STATE ---"
for rp in /sys/bus/remoteproc/devices/remoteproc*/; do
    name=$(cat "${rp}name" 2>/dev/null || basename "${rp}")
    state=$(cat "${rp}state" 2>/dev/null || echo "unknown")
    echo "  ${name}: ${state}"
done
```

**Critical patterns to flag:**
- `thermal thermal_zone: critical temperature reached` → immediate shutdown risk
- `cpu cpu0: cpufreq: cpufreq_online: Failed` → cpufreq driver issue
- `clk: failed to set` → clock tree problem, may prevent frequency scaling
- `remoteproc.*crashed` → M7 or M33 firmware crashed; may affect RPMsg/IPC performance
- `dma-pl330.*abort` → DMA engine errors causing I/O stalls
- `hung_task` → process stuck in uninterruptible sleep (D state)

**Record:** Count of errors, count of warnings, any critical patterns found.

---

### Step 7 — Synthesize Findings and Report

After completing all six investigation steps, synthesize the findings using the template below.
Fill in every field — use "None detected" or "N/A" where appropriate.

---

## Report Template

```
╔══════════════════════════════════════════════════════════════════════════╗
║           i.MX 95 Performance Investigation Report                      ║
╚══════════════════════════════════════════════════════════════════════════╝

Timestamp  : <UTC timestamp>
Board      : <model from /sys/firmware/devicetree/base/model>
SoC Rev    : <from /sys/devices/soc0/revision>
Kernel     : <uname -r>
Uptime     : <uptime>
Symptom    : <user-reported symptom>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 1 — THERMAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Max zone temp  : <°C>  (<zone name>)
  Throttling     : <YES / NO>
  Active cooling : <YES (state=N/max) / NO>
  Assessment     : <Normal / Warm / Throttling / Critical>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 2 — CPU FREQUENCY SCALING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Governor       : <governor name>
  CPU0–3 freq    : <MHz>
  CPU4–5 freq    : <MHz or OFFLINE>
  Max allowed    : <MHz>
  Assessment     : <OK / Capped / Governor misconfigured>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 3 — GPU / NPU STATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GPU freq       : <MHz or not detected>
  GPU governor   : <governor>
  NPU driver     : <loaded / not loaded>
  eIQ delegate   : <path or not found>
  Assessment     : <OK / Driver missing / Frequency capped>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 4 — MEMORY PRESSURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RAM available  : <MB> / <MB total>  (<% used>)
  CMA free       : <MB> / <MB total>  (<% used>)
  OOM events     : <count or none>
  Top consumer   : <process name> (<MB> RSS)
  Assessment     : <Healthy / Moderate / High / Critical>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 5 — IRQ LOAD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Top IRQ source : <name> at <rate>/sec
  IRQ storm      : <YES / NO>
  Assessment     : <Normal / Elevated / Storm detected>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDING 6 — KERNEL HEALTH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  dmesg errors   : <count>
  dmesg warnings : <count>
  Critical msgs  : <list or none>
  Remoteproc     : <M7: running/offline, M33: running/offline>
  Assessment     : <Clean / Minor warnings / Errors present / Critical>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ASSESSMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Primary cause  : <most likely root cause>
  Contributing   : <secondary factors if any>
  Confidence     : <High / Medium / Low>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOMMENDED ACTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. <Highest priority action — specific command or step>
  2. <Second action>
  3. <Third action>
  (Add more as needed)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
QUICK FIXES (safe to apply immediately)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  # Set performance governor on all cores:
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
      echo performance > "${cpu}"
  done

  # Unlock CPU max frequency:
  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
      echo 1800000 > "${cpu}"
  done

  # Free page cache (safe, kernel will reclaim as needed):
  echo 1 > /proc/sys/vm/drop_caches
```

---

## Decision Tree Summary

```
User reports: "board is slow"
        │
        ▼
Step 1: Diagnostic snapshot
        │
        ├─ dmesg has kernel panics/OOM? ──► Step 6 first, then Step 4
        │
        ▼
Step 2: Thermal check
        │
        ├─ Any zone ≥ 85°C? ──► PRIMARY CAUSE: thermal throttling
        │                        Recommend: cooling, reduce workload
        │
        ▼
Step 3: Frequency check
        │
        ├─ Governor = powersave? ──► PRIMARY CAUSE: governor misconfigured
        │                            Fix: echo schedutil > scaling_governor
        ├─ max_freq capped? ──────► PRIMARY CAUSE: frequency cap
        │                            Fix: echo 1800000 > scaling_max_freq
        │
        ▼
Step 4: Memory check
        │
        ├─ Available < 128 MB? ──► PRIMARY CAUSE: memory pressure
        │                          Recommend: kill unused processes, check CMA
        │
        ▼
Step 5: IRQ check
        │
        ├─ Any IRQ > 10k/sec? ──► CONTRIBUTING CAUSE: IRQ storm
        │                          Investigate driver, consider IRQ affinity
        │
        ▼
Step 6: dmesg check
        │
        ├─ Clock/regulator errors? ──► PRIMARY CAUSE: power domain issue
        ├─ remoteproc crashed? ──────► CONTRIBUTING: IPC overhead
        │
        ▼
Step 7: Synthesize → Report
```

---

## Common Root Causes on i.MX 95

| Symptom | Most Likely Cause | Quick Check |
|---------|-------------------|-------------|
| All CPUs at 300 MHz under load | Thermal throttle or powersave governor | Step 2 + Step 3 |
| NPU benchmark 10× slower than spec | eIQ delegate not loaded; falling back to CPU | Step 3c |
| Camera pipeline drops frames | CMA exhausted; DMA-BUF allocation failing | Step 4 |
| System sluggish after 10 min | Thermal throttle from sustained NPU+CPU load | Step 2 |
| Random process kills | OOM killer active | Step 4 + dmesg |
| Network throughput low | IRQ affinity; NET_RX softirq on single core | Step 5 |
| M7 firmware not responding | remoteproc crashed | Step 6 |
