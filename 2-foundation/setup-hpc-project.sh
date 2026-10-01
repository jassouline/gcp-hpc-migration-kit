#!/usr/bin/env bash
# ==============================================================================
# Sim2GCP — Isolated Google Cloud HPC Project & IAM Bootstrapper
# File: 2-foundation/setup-hpc-project.sh
#
# Description:
#   Creates a dedicated Google Cloud project for HPC/CAE simulations, links it
#   to your active Cloud Billing Account (so promotional/Startup credits apply),
#   grants scoped project access to your simulation engineers, and enables all
#   APIs required by Google Cloud Cluster Toolkit (Slurm v6).
#
# Usage:
#   ./2-foundation/setup-hpc-project.sh --project-id my-hpc-project [--billing-account 01XXXX-XXXXXX-XXXXXX] [--org-id 123456789] [--engineers "user1@example.com,user2@example.com"] [--dry-run]
# ==============================================================================

set -euo pipefail

PROJECT_ID=""
PROJECT_NAME="HPC Simulation Cluster"
BILLING_ACCOUNT_ID=""
ORG_ID=""
ENGINEERS_CSV=""
IAM_ROLE="roles/owner"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --project-id <PROJECT_ID> [options]

Required:
  --project-id <ID>          Unique GCP Project ID (6-30 chars, lowercase letters, digits, hyphens)

Optional:
  --project-name <NAME>      Display name for the project (default: "HPC Simulation Cluster")
  --billing-account <ID>     Cloud Billing Account ID (auto-detected if omitted)
  --org-id <ID>              Google Cloud Organization ID (auto-detected if omitted)
  --engineers <EMAILS>       Comma-separated list of engineer emails to grant access on this project
  --role <ROLE>              IAM role to grant engineers on this project (default: roles/owner)
  --dry-run                  Print gcloud commands without executing them
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --billing-account) BILLING_ACCOUNT_ID="$2"; shift 2 ;;
    --org-id) ORG_ID="$2"; shift 2 ;;
    --engineers) ENGINEERS_CSV="$2"; shift 2 ;;
    --role) IAM_ROLE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "${PROJECT_ID}" ]; then
  echo "Error: --project-id is required." >&2
  usage
  exit 1
fi

if ! [[ "${PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
  echo "Error: Invalid --project-id '${PROJECT_ID}'. Must be 6-30 characters, lowercase letters, digits, or hyphens, starting with a letter." >&2
  exit 1
fi

run_cmd() {
  echo "  \$ $*"
  if [ "${DRY_RUN}" -eq 0 ]; then
    "$@"
  fi
}

echo "========================================================================"
echo " Sim2GCP — Google Cloud HPC Project Bootstrapper"
echo " Target Project ID : ${PROJECT_ID}"
echo " Mode              : $([ "${DRY_RUN}" -eq 1 ] && echo "DRY-RUN (no changes)" || echo "LIVE EXECUTION")"
echo "========================================================================"

# 1. Auto-detect Billing Account & Organization if not provided
if [ -z "${BILLING_ACCOUNT_ID}" ]; then
  echo "[1/5] Detecting active Cloud Billing Account..."
  if [ "${DRY_RUN}" -eq 0 ]; then
    BILLING_ACCOUNT_ID=$(gcloud billing accounts list --filter="open=true" --format="value(ACCOUNT_ID)" --limit=1 2>/dev/null || true)
    if [ -z "${BILLING_ACCOUNT_ID}" ]; then
      EXISTING_BA=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
      BILLING_ACCOUNT_ID="${EXISTING_BA#billingAccounts/}"
    fi
  else
    BILLING_ACCOUNT_ID="01XXXX-XXXXXX-XXXXXX"
  fi
fi

if [ -z "${BILLING_ACCOUNT_ID}" ]; then
  echo "Error: Could not auto-detect an open Cloud Billing Account." >&2
  echo "Please pass --billing-account <ACCOUNT_ID> (find it at https://console.cloud.google.com/billing)." >&2
  exit 1
fi

DETECTED_ORG_ID="${ORG_ID}"
if [ -z "${DETECTED_ORG_ID}" ] && [ "${DRY_RUN}" -eq 0 ]; then
  DETECTED_ORG_ID=$(gcloud organizations list --format="value(ID)" --limit=1 2>/dev/null || true)
fi

echo "  -> Billing Account ID : ${BILLING_ACCOUNT_ID}"
echo "  -> Organization ID    : ${DETECTED_ORG_ID:-Auto / Default}"

# 2. Create the isolated project (if it doesn't already exist)
echo "[2/5] Creating isolated HPC project '${PROJECT_ID}'..."
if [ "${DRY_RUN}" -eq 0 ] && gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "  -> Project '${PROJECT_ID}' already exists, skipping creation."
else
  if [ -n "${ORG_ID}" ]; then
    run_cmd gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}" --organization="${ORG_ID}"
  else
    run_cmd gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}"
  fi
fi

# 3. Link Project to Cloud Billing Account
echo "[3/5] Linking project '${PROJECT_ID}' to Billing Account '${BILLING_ACCOUNT_ID}'..."
if [ "${DRY_RUN}" -eq 0 ] && [ "$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null || true)" = "True" ]; then
  echo "  -> Project '${PROJECT_ID}' already has active billing linked (${BILLING_ACCOUNT_ID})."
else
  run_cmd gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
fi
run_cmd gcloud config set project "${PROJECT_ID}"

# 4. Grant IAM permissions on the isolated HPC project
if [ -n "${ENGINEERS_CSV}" ]; then
  echo "[4/5] Granting '${IAM_ROLE}' on project '${PROJECT_ID}' to simulation engineers..."
  IFS=',' read -r -a EMAIL_ARRAY <<< "${ENGINEERS_CSV}"
  for raw_email in "${EMAIL_ARRAY[@]}"; do
    email=$(printf '%s' "${raw_email}" | tr -d '[:space:]')
    if [ -n "${email}" ]; then
      if ! [[ "${email}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "  [!] Skipping invalid email format: ${email}" >&2
        continue
      fi
      run_cmd gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="user:${email}" \
        --role="${IAM_ROLE}" \
        --condition=None
    fi
  done
else
  echo "[4/5] No --engineers specified, skipping additional IAM bindings."
fi

# 5. Enable required HPC, Storage, and Networking APIs
echo "[5/5] Enabling Google Cloud APIs required for Cluster Toolkit (Slurm + C3/H3 + Filestore NFS)..."
run_cmd gcloud services enable \
  compute.googleapis.com \
  file.googleapis.com \
  servicenetworking.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iap.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project="${PROJECT_ID}"

echo ""
echo "========================================================================"
echo " Project '${PROJECT_ID}' is ready for HPC deployment!"
echo " Next step: Verify your regional vCPU quotas before deploying Slurm:"
echo "   ./2-foundation/check-gcp-hpc-readiness.sh --project ${PROJECT_ID} --cores 512 --family C3 --region europe-west1"
echo "========================================================================"
