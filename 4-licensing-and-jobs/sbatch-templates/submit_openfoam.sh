#!/bin/bash
#SBATCH --job-name=openfoam-cfd
#SBATCH --output=/home/%u/logs/openfoam_%j.out
#SBATCH --error=/home/%u/logs/openfoam_%j.err
#SBATCH --partition=cfdh3                 # Or 'cfd' / 'cfdspot' on C3
#SBATCH --nodes=6                         # 6 x h3-standard-88 = 528 physical cores
#SBATCH --ntasks-per-node=88              # 88 MPI ranks per H3 node (44 on c3-standard-88)
#SBATCH --exclusive
#SBATCH --time=04:00:00

# ==============================================================================
# Sim2GCP — Multi-Node OpenFOAM Slurm Submission Script (H3 / C3)
# File: 4-licensing-and-jobs/sbatch-templates/submit_openfoam.sh
# ==============================================================================

set -euo pipefail

# 1. Load OpenFOAM environment
source /opt/openfoam/etc/bashrc || true

CASE_DIR="/home/${USER}/openfoam_cases/aerodynamics_${SLURM_JOB_ID}"
SOLVER="simpleFoam"

mkdir -p "/home/${USER}/logs"
cd "${CASE_DIR}"

echo "========================================================================"
echo " Running OpenFOAM (${SOLVER}) on ${SLURM_NTASKS} physical cores"
echo " Nodes: ${SLURM_NNODES} (${SLURM_JOB_NODELIST})"
echo "========================================================================"

# 2. Update numberOfSubdomains in system/decomposeParDict to match SLURM_NTASKS
if [ -f system/decomposeParDict ]; then
  sed -i "s/numberOfSubdomains[[:space:]]*[0-9]*;/numberOfSubdomains ${SLURM_NTASKS};/" system/decomposeParDict
fi

# 3. Decompose mesh, run parallel solver via MPI, and reconstruct
decomposePar -force > log.decomposePar 2>&1
mpirun -np "${SLURM_NTASKS}" --bind-to core "${SOLVER}" -parallel > "log.${SOLVER}" 2>&1
reconstructPar -latestTime > log.reconstructPar 2>&1

echo "OpenFOAM run finished successfully at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
