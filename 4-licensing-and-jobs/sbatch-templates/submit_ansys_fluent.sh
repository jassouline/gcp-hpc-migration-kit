#!/bin/bash
#SBATCH --job-name=ansys-fluent-cfd
#SBATCH --output=/home/%u/logs/fluent_%j.out
#SBATCH --error=/home/%u/logs/fluent_%j.err
#SBATCH --partition=cfd                   # Switch to 'cfdspot' for ~65% Spot VM savings
#SBATCH --nodes=12                        # 12 x c3-standard-88 (threads_per_core=1) = 528 physical cores
#SBATCH --ntasks-per-node=44              # 44 MPI ranks per node (1 rank per physical core)
#SBATCH --exclusive                       # Dedicated node allocation for deterministic MPI latency
#SBATCH --time=04:00:00

# ==============================================================================
# Sim2GCP — Multi-Node Ansys Fluent Slurm Submission Script (C3 / H3)
# File: 4-licensing-and-jobs/sbatch-templates/submit_ansys_fluent.sh
# ==============================================================================

set -euo pipefail

# 1. Configure BYOL Ansys License Server (Update IP/Hostname)
export ANSYSLMD_LICENSE_FILE="1055@10.0.0.10"
export ANSYSLI_SERVERS="2325@10.0.0.10"

# 2. Path to Ansys Fluent installation on shared NFS (/home) and simulation input
ANSYS_ROOT="/home/shared/ansys_inc/v242/fluent/bin"
WORKDIR="/home/${USER}/simulations/run_${SLURM_JOB_ID}"
JOURNAL_FILE="solve_transient.jou"
SOLVER_PRECISION="3ddp"                   # 3d or 3ddp (double precision)
MAX_SOLVER_CORES=512                      # Cap to match 512-core HPC license pack if needed

mkdir -p "${WORKDIR}" "/home/${USER}/logs"
cd "${WORKDIR}"

# 3. Generate Slurm hostfile for Ansys Fluent MPI
HOSTFILE="${WORKDIR}/slurm_hosts_${SLURM_JOB_ID}.txt"
scontrol show hostnames "${SLURM_JOB_NODELIST}" | awk -v tasks="${SLURM_NTASKS_PER_NODE}" '{print $0":"tasks}' > "${HOSTFILE}"

TOTAL_ALLOCATED=$(( SLURM_NNODES * SLURM_NTASKS_PER_NODE ))
CORES_TO_USE=$(( TOTAL_ALLOCATED > MAX_SOLVER_CORES ? MAX_SOLVER_CORES : TOTAL_ALLOCATED ))

echo "========================================================================"
echo " Starting Ansys Fluent (${SOLVER_PRECISION}) on ${CORES_TO_USE} physical cores"
echo " Nodes Allocated : ${SLURM_NNODES} (${SLURM_JOB_NODELIST})"
echo " Working Dir     : ${WORKDIR}"
echo "========================================================================"

# 4. Launch Ansys Fluent in batch mode over Intel MPI / TCP gVNIC
"${ANSYS_ROOT}/fluent" "${SOLVER_PRECISION}" \
  -g \
  -t"${CORES_TO_USE}" \
  -cnf="${HOSTFILE}" \
  -mpi=intel \
  -pib.infiniband=off \
  -i "${JOURNAL_FILE}"

echo "Simulation completed at $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
