#!/bin/bash
#SBATCH --job-name=abaqus-fea
#SBATCH --output=/home/%u/logs/abaqus_%j.out
#SBATCH --error=/home/%u/logs/abaqus_%j.err
#SBATCH --partition=feahighmem
#SBATCH --nodes=4                         # 4 x c3-highmem-176 = 352 physical cores & 5.6 TB RAM
#SBATCH --ntasks-per-node=88              # 88 physical cores per c3-highmem-176 node
#SBATCH --exclusive
#SBATCH --time=06:00:00

# ==============================================================================
# Sim2GCP — Multi-Node Abaqus FEA Slurm Submission Script (c3-highmem-176)
# File: 4-licensing-and-jobs/sbatch-templates/submit_abaqus_fea.sh
# ==============================================================================

set -euo pipefail

export ABAQUSLM_LICENSE_FILE="27000@10.0.0.10"
ABAQUS_BIN="/home/shared/SIMULIA/Commands/abaqus"
JOB_NAME="structural_thermal_model"
INPUT_FILE="${JOB_NAME}.inp"
SCRATCH_DIR="/tmp/abaqus_scratch_${SLURM_JOB_ID}"

mkdir -p "/home/${USER}/logs" "${SCRATCH_DIR}"

# Build Abaqus mp_host_split list from Slurm node allocation
MP_HOST_LIST="["
FIRST=1
for host in $(scontrol show hostnames "${SLURM_JOB_NODELIST}"); do
  if [ "${FIRST}" -eq 1 ]; then
    FIRST=0
  else
    MP_HOST_LIST="${MP_HOST_LIST},"
  fi
  MP_HOST_LIST="${MP_HOST_LIST}['${host}',${SLURM_NTASKS_PER_NODE}]"
done
MP_HOST_LIST="${MP_HOST_LIST}]"

cat > abaqus_v6.env <<EOF
mp_host_list=${MP_HOST_LIST}
scratch="${SCRATCH_DIR}"
EOF

echo "Launching Abaqus job '${JOB_NAME}' across ${SLURM_NTASKS} cores..."
"${ABAQUS_BIN}" job="${JOB_NAME}" input="${INPUT_FILE}" cpus="${SLURM_NTASKS}" mp_mode=mpi interactive

rm -rf "${SCRATCH_DIR}"
