#!/usr/bin/env bash
# ==============================================================================
# Sim2GCP — Google Cloud HPC Regional Quota & Zone Availability Checker
# File: 2-foundation/check-gcp-hpc-readiness.sh
#
# Description:
#   Audits a Google Cloud project's live regional vCPU quotas (C3_CPUS, H3_CPUS,
#   C3D_CPUS, C4_CPUS) and zone machine-type availability before deploying a
#   Slurm cluster with Cluster Toolkit.
#   Automatically accounts for Simultaneous Multithreading disabled
#   (threads_per_core=1) where 1 physical core = 2 nominal vCPUs of quota on
#   C3/C3D/C4, and 1 vCPU on H3.
#
# Usage:
#   ./2-foundation/check-gcp-hpc-readiness.sh [--project PROJECT_ID] [--cores 512] [--family C3|H3|C3D|C4] [--region europe-west1] [--offline]
# ==============================================================================

set -euo pipefail

PROJECT_ID=""
TARGET_CORES=512
FAMILY="C3"
REGION="europe-west1"
HIGHMEM=0
OFFLINE=0

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --project <PROJECT_ID>   GCP Project ID (defaults to active gcloud project)
  --cores <INT>            Target physical cores for MPI solver runs (default: 512)
  --family <C3|H3|C3D|C4>  Target GCP compute family (default: C3)
  --region <REGION>        Target GCP region (default: europe-west1)
  --highmem                Use high-memory machine variant (8 GB/vCPU = 16 GB/physical core)
  --offline                Run sizing & quota calculation without calling gcloud API
  -h, --help               Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_ID="$2"; shift 2 ;;
    --cores) TARGET_CORES="$2"; shift 2 ;;
    --family) FAMILY=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]'); shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --highmem) HIGHMEM=1; shift ;;
    --offline) OFFLINE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if ! [[ "${TARGET_CORES}" =~ ^[0-9]+$ ]] || [ "${TARGET_CORES}" -lt 1 ]; then
  echo "Error: --cores must be a positive integer." >&2
  exit 1
fi

if ! [[ "${REGION}" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
  echo "Error: Invalid --region format '${REGION}' (example: europe-west1, europe-west4, us-central1)." >&2
  exit 1
fi

case "${FAMILY}" in
  C3)
    QUOTA_METRIC="C3_CPUS"
    if [ "${HIGHMEM}" -eq 1 ]; then
      MACHINE_TYPE="c3-highmem-176"
      PHY_PER_NODE=88
      VCPU_PER_NODE=176
      RAM_PER_NODE=1408
    else
      MACHINE_TYPE="c3-standard-88"
      PHY_PER_NODE=44
      VCPU_PER_NODE=88
      RAM_PER_NODE=352
    fi
    ;;
  H3)
    QUOTA_METRIC="H3_CPUS"
    MACHINE_TYPE="h3-standard-88"
    PHY_PER_NODE=88
    VCPU_PER_NODE=88
    RAM_PER_NODE=352
    ;;
  C3D)
    QUOTA_METRIC="C3D_CPUS"
    if [ "${HIGHMEM}" -eq 1 ]; then
      MACHINE_TYPE="c3d-highmem-180"
    else
      MACHINE_TYPE="c3d-standard-180"
    fi
    PHY_PER_NODE=90
    VCPU_PER_NODE=180
    RAM_PER_NODE=$([ "${HIGHMEM}" -eq 1 ] && echo 1440 || echo 720)
    ;;
  C4)
    QUOTA_METRIC="C4_CPUS"
    if [ "${HIGHMEM}" -eq 1 ]; then
      MACHINE_TYPE="c4-highmem-192"
    else
      MACHINE_TYPE="c4-standard-192"
    fi
    PHY_PER_NODE=96
    VCPU_PER_NODE=192
    RAM_PER_NODE=$([ "${HIGHMEM}" -eq 1 ] && echo 1488 || echo 720)
    ;;
  *)
    echo "Error: Unsupported --family '${FAMILY}'. Choose one of: C3, H3, C3D, C4." >&2
    exit 1
    ;;
esac

NODES_NEEDED=$(( (TARGET_CORES + PHY_PER_NODE - 1) / PHY_PER_NODE ))
TOTAL_PHY_CORES=$(( NODES_NEEDED * PHY_PER_NODE ))
REQUIRED_VCPU_QUOTA=$(( NODES_NEEDED * VCPU_PER_NODE ))
# Recommend ~15% headroom rounded to next multiple of VCPU_PER_NODE (at least +1 node buffer)
RECOMMENDED_QUOTA=$(( (NODES_NEEDED + 1) * VCPU_PER_NODE ))
TOTAL_RAM_GB=$(( NODES_NEEDED * RAM_PER_NODE ))

echo "========================================================================"
echo " Sim2GCP — Google Cloud HPC Quota & Zone Availability Checker"
echo "========================================================================"
echo " Target Solver Cores       : ${TARGET_CORES} physical cores (MPI ranks)"
echo " Selected Machine Type     : ${MACHINE_TYPE} (Family: ${FAMILY})"
echo " Node Sizing (SMT=Off)     : ${NODES_NEEDED} nodes x ${PHY_PER_NODE} physical cores = ${TOTAL_PHY_CORES} physical cores"
echo " Total Cluster Memory      : ${TOTAL_RAM_GB} GB DDR5"
echo " Nominal vCPU Quota Needed : ${REQUIRED_VCPU_QUOTA} ${QUOTA_METRIC} (Recommended request: ${RECOMMENDED_QUOTA} ${QUOTA_METRIC})"
echo " Target Region             : ${REGION}"
echo "------------------------------------------------------------------------"

if [ "${OFFLINE}" -eq 0 ] && command -v gcloud >/dev/null 2>&1; then
  if [ -z "${PROJECT_ID}" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  fi
fi

if [ "${OFFLINE}" -eq 1 ] || [ -z "${PROJECT_ID}" ]; then
  echo "[Mode: Offline Calculator — pass --project <PROJECT_ID> in Cloud Shell for live quota verification]"
  CURRENT_LIMIT="UNKNOWN"
else
  echo "[1/2] Checking live regional quota '${QUOTA_METRIC}' on project '${PROJECT_ID}' in '${REGION}'..."
  QUOTA_LINE=$(gcloud compute regions describe "${REGION}" \
    --project="${PROJECT_ID}" \
    --flatten="quotas[]" \
    --format="csv[no-heading](quotas.metric,quotas.limit,quotas.usage)" 2>/dev/null \
    | awk -F, -v m="${QUOTA_METRIC}" '$1 == m {printf "%d %d\n", $2, $3}' || true)

  CURRENT_LIMIT=$(echo "${QUOTA_LINE}" | awk '{print $1}' 2>/dev/null || echo "0")
  CURRENT_USAGE=$(echo "${QUOTA_LINE}" | awk '{print $2}' 2>/dev/null || echo "0")
  [ -z "${CURRENT_LIMIT}" ] && CURRENT_LIMIT=0
  [ -z "${CURRENT_USAGE}" ] && CURRENT_USAGE=0

  echo "  -> Current '${QUOTA_METRIC}' Limit in ${REGION} : ${CURRENT_LIMIT} vCPUs (Current usage: ${CURRENT_USAGE} vCPUs)"

  echo "[2/2] Checking zones in '${REGION}' offering '${MACHINE_TYPE}'..."
  REGION_ZONES_CSV=$(gcloud compute regions describe "${REGION}" \
    --project="${PROJECT_ID}" \
    --format="value(zones.basename())" 2>/dev/null | tr ';' ',' | tr '\n' ',' | sed 's/,$//' || true)

  if [ -n "${REGION_ZONES_CSV}" ]; then
    AVAILABLE_ZONES=$(gcloud compute machine-types list \
      --project="${PROJECT_ID}" \
      --zones="${REGION_ZONES_CSV}" \
      --filter="name=${MACHINE_TYPE}" \
      --format="value(zone)" 2>/dev/null | tr '\n' ' ' || true)
  else
    AVAILABLE_ZONES=""
  fi

  if [ -n "${AVAILABLE_ZONES}" ]; then
    echo "  -> Available Zones in ${REGION} : ${AVAILABLE_ZONES}"
  else
    if [ "${FAMILY}" = "H3" ]; then
      echo "  -> [!] Warning: '${MACHINE_TYPE}' is not offered in '${REGION}'. For H3, use '--region europe-west4' (zones b/c) or '--region us-central1' (zone a)."
    else
      echo "  -> [!] Warning: '${MACHINE_TYPE}' was not listed in '${REGION}'. Consider checking europe-west1, europe-west4, or us-central1."
    fi
  fi
fi

echo "------------------------------------------------------------------------"

if [[ "${CURRENT_LIMIT}" =~ ^[0-9]+$ ]] && [ "${CURRENT_LIMIT}" -ge "${REQUIRED_VCPU_QUOTA}" ]; then
  echo "[STATUS: READY] Your regional quota (${CURRENT_LIMIT} ${QUOTA_METRIC}) covers your ${TARGET_CORES}-core cluster (${REQUIRED_VCPU_QUOTA} ${QUOTA_METRIC})!"
else
  if [[ "${CURRENT_LIMIT}" =~ ^[0-9]+$ ]]; then
    echo "[STATUS: QUOTA INCREASE NEEDED] Current limit is ${CURRENT_LIMIT} ${QUOTA_METRIC}, but ${REQUIRED_VCPU_QUOTA} ${QUOTA_METRIC} are required."
  else
    echo "[QUOTA CHECKLIST] Verify in the Console that your ${QUOTA_METRIC} limit in ${REGION} is at least ${REQUIRED_VCPU_QUOTA} vCPUs."
  fi
  cat <<EOF

How to request your Quota Increase in 2 minutes:
  1. Open: https://console.cloud.google.com/iam-admin/quotas?project=${PROJECT_ID:-YOUR_PROJECT_ID}
  2. Filter by:
       Metric   : ${QUOTA_METRIC}
       Location : ${REGION}
  3. Select the row, click "Edit Quotas", and enter:
       New Limit : ${RECOMMENDED_QUOTA}
  4. Paste this ready-made technical justification:
     "Deploying an auto-scaling Cloud HPC Toolkit (Slurm v6) cluster in ${REGION}
      for CAE/CFD engineering simulations (${TARGET_CORES} physical cores across ${NODES_NEEDED}
      ${MACHINE_TYPE} nodes with threads_per_core=1 and COMPACT placement policy).
      Cluster uses Scale-to-Zero between simulation runs."
EOF
fi
echo "========================================================================"
