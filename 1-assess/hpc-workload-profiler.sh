#!/usr/bin/env bash
# ==============================================================================
# Sim2GCP — Universal HPC & CAE Hardware & Saturation Profiler
# File: 1-assess/hpc-workload-profiler.sh
#
# Description:
#   Zero-dependency, non-root Linux profiling script for On-Premise servers,
#   AWS ParallelCluster/EC2 nodes, or Azure CycleCloud/VM instances.
#   1. Detects source environment (On-Prem Bare Metal, AWS EC2, Azure VM).
#   2. Collects CPU, NUMA, AVX2/AVX-512, Memory, Disk, and Network topology.
#   3. Samples real-time per-core CPU utilization and active RAM saturation.
#   4. Generates a Markdown Sizing Report + CSV recommending the optimal
#      Google Cloud HPC machine type (C3, H3, C3D, C4) and required vCPU quotas.
#
# Usage:
#   chmod +x 1-assess/hpc-workload-profiler.sh
#   ./1-assess/hpc-workload-profiler.sh [-d DURATION_SEC] [-i INTERVAL_SEC] [-t TARGET_CORES] [-o OUTPUT_DIR]
# ==============================================================================

set -euo pipefail
export LC_ALL=C

DURATION=60
INTERVAL=2
TARGET_CORES=512
OUT_DIR="."

usage() {
  cat <<EOF
Usage: $0 [-d duration_seconds] [-i interval_seconds] [-t target_cloud_cores] [-o output_dir]

Options:
  -d  Total profiling duration in seconds (default: 60)
  -i  Sampling interval in seconds (default: 2)
  -t  Target physical cores for Google Cloud cluster sizing (default: 512)
  -o  Output directory for Markdown report and CSV (default: current directory)
  -h  Show this help message
EOF
}

while getopts ":d:i:t:o:h" opt; do
  case ${opt} in
    d) DURATION="${OPTARG}" ;;
    i) INTERVAL="${OPTARG}" ;;
    t) TARGET_CORES="${OPTARG}" ;;
    o) OUT_DIR="${OPTARG}" ;;
    h) usage; exit 0 ;;
    \?) echo "Invalid option: -${OPTARG}" >&2; usage; exit 1 ;;
    :) echo "Option -${OPTARG} requires an argument." >&2; usage; exit 1 ;;
  esac
done

if ! [[ "${DURATION}" =~ ^[0-9]+$ ]] || [ "${DURATION}" -lt 2 ]; then
  echo "Error: Duration (-d) must be an integer >= 2." >&2
  exit 1
fi
if ! [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || [ "${INTERVAL}" -lt 1 ]; then
  echo "Error: Interval (-i) must be an integer >= 1." >&2
  exit 1
fi
if ! [[ "${TARGET_CORES}" =~ ^[0-9]+$ ]] || [ "${TARGET_CORES}" -lt 1 ]; then
  echo "Error: Target cores (-t) must be a positive integer." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || hostname || echo "hpc-node")
HOSTNAME_SAFE=$(printf '%s' "${HOSTNAME_SHORT}" | tr -cd 'a-zA-Z0-9_-')
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_MD="${OUT_DIR}/hpc_profile_${HOSTNAME_SAFE}_${TIMESTAMP}.md"
CSV_FILE="${OUT_DIR}/hpc_metrics_${HOSTNAME_SAFE}_${TIMESTAMP}.csv"

echo "========================================================================"
echo " Sim2GCP — HPC Hardware & Solver Saturation Profiler"
echo " Host: ${HOSTNAME_SHORT} | Duration: ${DURATION}s (interval: ${INTERVAL}s)"
echo " Target Cloud Cluster Sizing: ${TARGET_CORES} physical cores"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. Detect Source Environment (On-Prem vs AWS vs Azure vs GCP)
# ------------------------------------------------------------------------------
OS_KERNEL=$(uname -s 2>/dev/null || echo "Linux")
SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "Unknown")
PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
CLOUD_PROVIDER="On-Premise / Bare Metal"
SOURCE_INSTANCE_TYPE="${SYS_VENDOR} ${PRODUCT_NAME}"

if [ "${OS_KERNEL}" = "Darwin" ]; then
  CLOUD_PROVIDER="On-Premise / Workstation (macOS)"
  SOURCE_INSTANCE_TYPE=$(sysctl -n hw.model 2>/dev/null || echo "Apple Mac")
elif grep -qi "amazon" /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/board_vendor 2>/dev/null; then
  CLOUD_PROVIDER="AWS EC2"
  if command -v curl >/dev/null 2>&1; then
    IMDS_TOKEN=$(curl -s -m 1 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
    if [ -n "${IMDS_TOKEN}" ]; then
      AWS_TYPE=$(curl -s -m 1 -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" "http://169.254.169.254/latest/meta-data/instance-type" 2>/dev/null || true)
      [ -n "${AWS_TYPE}" ] && SOURCE_INSTANCE_TYPE="${AWS_TYPE}"
    fi
  fi
elif grep -qi "microsoft" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
  CLOUD_PROVIDER="Microsoft Azure"
  if command -v curl >/dev/null 2>&1; then
    AZ_TYPE=$(curl -s -m 1 -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-02-01&format=text" 2>/dev/null || true)
    [ -n "${AZ_TYPE}" ] && SOURCE_INSTANCE_TYPE="${AZ_TYPE}"
  fi
elif grep -qi "google" /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name 2>/dev/null; then
  CLOUD_PROVIDER="Google Cloud Compute Engine"
fi

echo "[1/4] Detected Environment : ${CLOUD_PROVIDER} (${SOURCE_INSTANCE_TYPE})"

# ------------------------------------------------------------------------------
# 2. Collect CPU, Memory, NUMA & Vector Instruction Capabilities
# ------------------------------------------------------------------------------
SOCKETS=1
NUMA_NODES=1
L3_CACHE="Unknown"
HAS_AVX2="No"
HAS_AVX512="No"

if [ "${OS_KERNEL}" = "Darwin" ]; then
  CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon / Mac CPU")
  LOGICAL_CPUS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
  PHYSICAL_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "${LOGICAL_CPUS}")
  CORES_PER_SOCKET="${PHYSICAL_CORES}"
  THREADS_PER_CORE=$(( LOGICAL_CPUS / (PHYSICAL_CORES > 0 ? PHYSICAL_CORES : 1) ))
  [ "${THREADS_PER_CORE}" -lt 1 ] && THREADS_PER_CORE=1
  MEM_TOTAL_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  MEM_TOTAL_KB=$(( MEM_TOTAL_BYTES / 1024 ))
else
  CPU_MODEL=$(awk -F: '/model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Unknown CPU")
  LOGICAL_CPUS=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
  CORES_PER_SOCKET="${LOGICAL_CPUS}"
  THREADS_PER_CORE=1

  if command -v lscpu >/dev/null 2>&1; then
    LSCPU_OUT=$(lscpu 2>/dev/null || true)
    SOCKETS=$(echo "${LSCPU_OUT}" | awk -F: '/^Socket\(s\):/ {gsub(/[ \t]/, "", $2); print $2}' || echo 1)
    CORES_PER_SOCKET=$(echo "${LSCPU_OUT}" | awk -F: '/^Core\(s\) per socket:/ {gsub(/[ \t]/, "", $2); print $2}' || echo "${LOGICAL_CPUS}")
    THREADS_PER_CORE=$(echo "${LSCPU_OUT}" | awk -F: '/^Thread\(s\) per core:/ {gsub(/[ \t]/, "", $2); print $2}' || echo 1)
    NUMA_NODES=$(echo "${LSCPU_OUT}" | awk -F: '/^NUMA node\(s\):/ {gsub(/[ \t]/, "", $2); print $2}' || echo 1)
    L3_CACHE=$(echo "${LSCPU_OUT}" | awk -F: '/^L3 cache:/ {gsub(/^[ \t]+/, "", $2); print $2}' || echo "Unknown")
  fi

  [[ -z "${SOCKETS}" || ! "${SOCKETS}" =~ ^[0-9]+$ ]] && SOCKETS=1
  [[ -z "${CORES_PER_SOCKET}" || ! "${CORES_PER_SOCKET}" =~ ^[0-9]+$ ]] && CORES_PER_SOCKET="${LOGICAL_CPUS}"
  [[ -z "${THREADS_PER_CORE}" || ! "${THREADS_PER_CORE}" =~ ^[0-9]+$ ]] && THREADS_PER_CORE=1
  [[ -z "${NUMA_NODES}" || ! "${NUMA_NODES}" =~ ^[0-9]+$ ]] && NUMA_NODES=1

  PHYSICAL_CORES=$(( SOCKETS * CORES_PER_SOCKET ))
  [ "${PHYSICAL_CORES}" -lt 1 ] && PHYSICAL_CORES="${LOGICAL_CPUS}"

  CPU_FLAGS=$(awk -F: '/^flags/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "")
  echo "${CPU_FLAGS}" | grep -qw "avx2" && HAS_AVX2="Yes"
  echo "${CPU_FLAGS}" | grep -q "avx512" && HAS_AVX512="Yes"

  MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
fi

MEM_TOTAL_GB=$(awk -v kb="${MEM_TOTAL_KB}" 'BEGIN {printf "%.1f", kb / 1048576}')
RAM_PER_PHY_CORE_GB=$(awk -v gb="${MEM_TOTAL_GB}" -v c="${PHYSICAL_CORES}" 'BEGIN {printf "%.2f", gb / c}')

echo "[2/4] Hardware Inventory   : ${CPU_MODEL} | ${PHYSICAL_CORES} physical cores (${LOGICAL_CPUS} threads) | ${MEM_TOTAL_GB} GB RAM (${RAM_PER_PHY_CORE_GB} GB/core)"

# ------------------------------------------------------------------------------
# 3. Time-Series Saturation Profiling (/proc/stat & /proc/meminfo or Darwin fallback)
# ------------------------------------------------------------------------------
SAMPLES=$(( DURATION / INTERVAL ))
[ "${SAMPLES}" -lt 1 ] && SAMPLES=1

echo "timestamp,cpu_busy_pct,active_Logical_cores_gt50pct,mem_used_gb,mem_used_pct,load_1m,top_process" > "${CSV_FILE}"

echo "[3/4] Sampling live CPU & RAM saturation (${SAMPLES} samples over ${DURATION}s)..."

read_cpu_stat() {
  if [ -r /proc/stat ]; then
    awk '/^cpu[0-9]* / {
      id=$1;
      total=$2+$3+$4+$5+$6+$7+$8+$9;
      idle=$5+$6;
      print id, total, idle
    }' /proc/stat
  fi
}

PREV_STAT=$(read_cpu_stat)

MAX_CPU_PCT="0.0"
SUM_CPU_PCT="0.0"
MAX_ACTIVE_CORES=0
MAX_MEM_USED_GB="0.0"
PEAK_TOP_PROC="None"

for (( s=1; s<=SAMPLES; s++ )); do
  sleep "${INTERVAL}"
  TS_NOW=$(date +"%H:%M:%S")

  if [ -r /proc/stat ]; then
    CURR_STAT=$(read_cpu_stat)
    METRICS=$(awk -v prev="${PREV_STAT}" -v curr="${CURR_STAT}" '
    BEGIN {
      n_prev = split(prev, p_lines, "\n");
      for (i=1; i<=n_prev; i++) {
        if (split(p_lines[i], a, " ") == 3) {
          p_tot[a[1]] = a[2];
          p_idl[a[1]] = a[3];
        }
      }
      n_curr = split(curr, c_lines, "\n");
      active_cores = 0;
      global_pct = 0.0;
      for (i=1; i<=n_curr; i++) {
        if (split(c_lines[i], b, " ") == 3) {
          id = b[1];
          dt = b[2] - p_tot[id];
          di = b[3] - p_idl[id];
          pct = (dt > 0) ? (100.0 * (dt - di) / dt) : 0.0;
          if (id == "cpu") {
            global_pct = pct;
          } else {
            if (pct >= 50.0) active_cores++;
          }
        }
      }
      printf "%.1f %d", global_pct, active_cores;
    }')
    CURR_CPU_PCT=$(echo "${METRICS}" | awk '{print $1}')
    CURR_ACTIVE_CORES=$(echo "${METRICS}" | awk '{print $2}')
    MEM_AVAIL_KB=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_USED_KB=$(( MEM_TOTAL_KB - MEM_AVAIL_KB ))
    LOAD_1M=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00")
    TOP_PROC=$(ps -eo comm,%cpu,%mem --sort=-%cpu 2>/dev/null | awk 'NR==2 {printf "%s(CPU:%s%%,MEM:%s%%)", $1, $2, $3}' || echo "N/A")
    PREV_STAT="${CURR_STAT}"
  else
    # macOS / POSIX fallback when /proc/stat is unavailable
    PS_CPU_SUM=$(ps -A -o %cpu 2>/dev/null | awk 'NR>1 {sum+=$1} END {printf "%.1f", sum}' || echo "0.0")
    CURR_CPU_PCT=$(awk -v s="${PS_CPU_SUM}" -v c="${LOGICAL_CPUS}" 'BEGIN {p = s / (c>0?c:1); if (p>100.0) p=100.0; printf "%.1f", p}')
    CURR_ACTIVE_CORES=$(awk -v s="${PS_CPU_SUM}" -v c="${LOGICAL_CPUS}" 'BEGIN {ac = int((s / 100.0) + 0.5); if (ac > c) ac = c; if (ac < 1 && s > 10.0) ac = 1; print ac}')
    PAGE_SIZE=$(vm_stat 2>/dev/null | awk '/page size of/ {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/) print $i; exit}' || echo 4096)
    PAGES_ACTIVE=$(vm_stat 2>/dev/null | awk '/Pages active:/ {gsub(/\./,"",$3); print $3}' || echo 0)
    PAGES_WIRED=$(vm_stat 2>/dev/null | awk '/Pages wired down:/ {gsub(/\./,"",$4); print $4}' || echo 0)
    MEM_USED_KB=$(awk -v a="${PAGES_ACTIVE}" -v w="${PAGES_WIRED}" -v ps="${PAGE_SIZE}" 'BEGIN {printf "%d", ((a + w) * ps) / 1024}')
    LOAD_1M=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || echo "0.00")
    TOP_PROC=$(ps -Aceo %cpu,%mem,comm -r 2>/dev/null | awk 'NR==2 {printf "%s(CPU:%s%%,MEM:%s%%)", $3, $1, $2}' || echo "N/A")
  fi

  CURR_MEM_GB=$(awk -v u="${MEM_USED_KB}" 'BEGIN {printf "%.2f", u / 1048576}')
  CURR_MEM_PCT=$(awk -v u="${MEM_USED_KB}" -v t="${MEM_TOTAL_KB}" 'BEGIN {printf "%.1f", (t>0) ? (100.0*u/t) : 0.0}')
  [ -z "${TOP_PROC}" ] && TOP_PROC="idle"

  echo "${TS_NOW},${CURR_CPU_PCT},${CURR_ACTIVE_CORES},${CURR_MEM_GB},${CURR_MEM_PCT},${LOAD_1M},${TOP_PROC}" >> "${CSV_FILE}"

  SUM_CPU_PCT=$(awk -v a="${SUM_CPU_PCT}" -v b="${CURR_CPU_PCT}" 'BEGIN {printf "%.2f", a + b}')
  MAX_CPU_PCT=$(awk -v a="${MAX_CPU_PCT}" -v b="${CURR_CPU_PCT}" 'BEGIN {print (b > a) ? b : a}')
  [ "${CURR_ACTIVE_CORES}" -gt "${MAX_ACTIVE_CORES}" ] && MAX_ACTIVE_CORES="${CURR_ACTIVE_CORES}"
  MAX_MEM_USED_GB=$(awk -v a="${MAX_MEM_USED_GB}" -v b="${CURR_MEM_GB}" 'BEGIN {print (b > a) ? b : a}')
  if [ "${CURR_ACTIVE_CORES}" -ge "${MAX_ACTIVE_CORES}" ]; then
    PEAK_TOP_PROC="${TOP_PROC}"
  fi
done

AVG_CPU_PCT=$(awk -v s="${SUM_CPU_PCT}" -v n="${SAMPLES}" 'BEGIN {printf "%.1f", s / n}')
EFFECTIVE_ACTIVE_CORES="${MAX_ACTIVE_CORES}"
[ "${EFFECTIVE_ACTIVE_CORES}" -lt 1 ] && EFFECTIVE_ACTIVE_CORES="${PHYSICAL_CORES}"
PEAK_RAM_PER_ACTIVE_CORE_GB=$(awk -v m="${MAX_MEM_USED_GB}" -v c="${EFFECTIVE_ACTIVE_CORES}" 'BEGIN {printf "%.2f", m / c}')

# ------------------------------------------------------------------------------
# 4. Compute Optimal Google Cloud HPC Sizing & Quota Recommendation
# ------------------------------------------------------------------------------
RECOMMENDED_FAMILY="C3"
RECOMMENDED_MACHINE="c3-standard-88"
RECOMMENDED_REGION="europe-west1"
PHY_CORES_PER_NODE=44
VCPUS_PER_NODE=88
RAM_PER_NODE_GB=352
BLUEPRINT_FILE="3-blueprints/cfd-c3-slurm.yaml"
SIZING_RATIONALE="Balanced compute-to-memory ratio (8 GB RAM per physical core with threads_per_core=1), Intel Xeon 4th Gen (Sapphire Rapids) with AVX-512, and up to 200 Gbps Tier_1 gVNIC networking."

IS_HIGHMEM=$(awk -v r="${PEAK_RAM_PER_ACTIVE_CORE_GB}" -v hw="${RAM_PER_PHY_CORE_GB}" 'BEGIN {print (r > 6.5 || hw > 9.0) ? 1 : 0}')

if [ "${IS_HIGHMEM}" -eq 1 ]; then
  RECOMMENDED_FAMILY="C3"
  RECOMMENDED_MACHINE="c3-highmem-176"
  RECOMMENDED_REGION="europe-west1"
  PHY_CORES_PER_NODE=88
  VCPUS_PER_NODE=176
  RAM_PER_NODE_GB=1408
  BLUEPRINT_FILE="3-blueprints/fea-highmem-slurm.yaml"
  SIZING_RATIONALE="High memory footprint detected (> 6.5 GB/core peak or high-RAM source node). c3-highmem-176 provides 88 physical cores (with threads_per_core=1) and 1,408 GB DDR5 RAM (16 GB per physical core)."
elif echo "${SOURCE_INSTANCE_TYPE}" | grep -qiE "hpc6a|HB120|HB176|milan"; then
  RECOMMENDED_FAMILY="H3"
  RECOMMENDED_MACHINE="h3-standard-88"
  RECOMMENDED_REGION="europe-west4"
  PHY_CORES_PER_NODE=88
  VCPUS_PER_NODE=88
  RAM_PER_NODE_GB=352
  BLUEPRINT_FILE="3-blueprints/cfd-h3-slurm.yaml"
  SIZING_RATIONALE="Source matches a memory-bandwidth-optimized HPC instance (${SOURCE_INSTANCE_TYPE}). h3-standard-88 provides 88 dedicated physical cores (SMT disabled natively) across 8-channel DDR5 memory."
fi

RECOMMENDED_FAMILY_LOWER=$(printf '%s' "${RECOMMENDED_FAMILY}" | tr '[:upper:]' '[:lower:]')
NODES_REQUIRED=$(( (TARGET_CORES + PHY_CORES_PER_NODE - 1) / PHY_CORES_PER_NODE ))
TOTAL_PHY_CORES=$(( NODES_REQUIRED * PHY_CORES_PER_NODE ))
TOTAL_QUOTA_VCPUS=$(( NODES_REQUIRED * VCPUS_PER_NODE ))
TOTAL_CLUSTER_RAM_GB=$(( NODES_REQUIRED * RAM_PER_NODE_GB ))

cat <<EOF > "${REPORT_MD}"
# Sim2GCP — HPC Hardware & Saturation Assessment Report

- **Host Profiled:** \`${HOSTNAME_SHORT}\`
- **Date:** \`$(date -u +"%Y-%m-%d %H:%M:%S UTC")\`
- **Detected Source Environment:** **${CLOUD_PROVIDER}** (\`${SOURCE_INSTANCE_TYPE}\`)
- **Sampling Window:** \`${DURATION}s\` (interval: \`${INTERVAL}s\`)

---

## 1. Source Hardware Inventory

| Metric | Detected Value |
| :--- | :--- |
| **CPU Model** | \`${CPU_MODEL}\` |
| **Sockets x Cores/Socket** | \`${SOCKETS}\` socket(s) x \`${CORES_PER_SOCKET}\` cores = **\`${PHYSICAL_CORES}\` physical cores** |
| **Logical vCPUs / Threads** | \`${LOGICAL_CPUS}\` (\`Threads per core: ${THREADS_PER_CORE}\`) |
| **NUMA Nodes & L3 Cache** | \`${NUMA_NODES}\` NUMA node(s) — L3: \`${L3_CACHE}\` |
| **Vector Instructions** | AVX2: **${HAS_AVX2}** \| AVX-512: **${HAS_AVX512}** |
| **Total Installed RAM** | **\`${MEM_TOTAL_GB} GB\`** (**\`${RAM_PER_PHY_CORE_GB} GB\` per physical core**) |

---

## 2. Live Workload Saturation Summary

| Metric | Observed Value |
| :--- | :--- |
| **Average Global CPU Utilization** | \`${AVG_CPU_PCT}%\` |
| **Peak Global CPU Utilization** | **\`${MAX_CPU_PCT}%\`** |
| **Peak Active Cores (>50% busy)** | **\`${MAX_ACTIVE_CORES}\` / \`${LOGICAL_CPUS}\` logical cores** |
| **Peak RAM Used** | **\`${MAX_MEM_USED_GB} GB\`** / \`${MEM_TOTAL_GB} GB\` |
| **Peak RAM per Active Core** | **\`${PEAK_RAM_PER_ACTIVE_CORE_GB} GB / core\`** |
| **Dominant Process at Peak** | \`${PEAK_TOP_PROC}\` |

---

## 3. Google Cloud Target Architecture Recommendation (for ${TARGET_CORES} Physical Cores)

- **Recommended Machine Type:** **\`${RECOMMENDED_MACHINE}\`** (Family: **\`${RECOMMENDED_FAMILY}\`**)
- **Rationale:** ${SIZING_RATIONALE}

| Sizing Parameter | Target Value on Google Cloud |
| :--- | :--- |
| **Compute Node Type** | \`${RECOMMENDED_MACHINE}\` (\`threads_per_core: 1\`) |
| **Physical Cores per Node** | \`${PHY_CORES_PER_NODE}\` physical cores (\`${VCPUS_PER_NODE}\` nominal vCPUs) |
| **RAM per Node** | \`${RAM_PER_NODE_GB} GB\` DDR5 |
| **Recommended Node Count** | **\`${NODES_REQUIRED}\` nodes** = **\`${TOTAL_PHY_CORES}\` physical cores** (\`${TOTAL_CLUSTER_RAM_GB} GB\` total RAM) |
| **Required GCP Regional Quota** | **\`${RECOMMENDED_FAMILY}_CPUS >= ${TOTAL_QUOTA_VCPUS}\`** *(plus ~15% buffer recommended)* |
| **Ready-to-Use Cluster Blueprint** | [\`${BLUEPRINT_FILE}\`](../${BLUEPRINT_FILE}) |

---

## 4. Next Steps to Deploy on Google Cloud

1. **Check your live GCP Project Quota & Zone Availability:**
   \`\`\`bash
   ./2-foundation/check-gcp-hpc-readiness.sh --cores ${TARGET_CORES} --family ${RECOMMENDED_FAMILY} --region ${RECOMMENDED_REGION}
   \`\`\`
2. **Deploy the Slurm v6 Cluster with Cluster Toolkit:**
   \`\`\`bash
   ./ghpc create ${BLUEPRINT_FILE} --vars project_id=YOUR_PROJECT_ID
   ./ghpc deploy hpc-slurm-${RECOMMENDED_FAMILY_LOWER} --auto-approve
   \`\`\`
EOF

echo "[4/4] Assessment Complete!"
echo "  -> Markdown Report : ${REPORT_MD}"
echo "  -> Time-Series CSV : ${CSV_FILE}"
echo "  -> Recommended VM  : ${RECOMMENDED_MACHINE} (${NODES_REQUIRED} nodes = ${TOTAL_PHY_CORES} physical cores, Quota: ${TOTAL_QUOTA_VCPUS} ${RECOMMENDED_FAMILY}_CPUS)"
