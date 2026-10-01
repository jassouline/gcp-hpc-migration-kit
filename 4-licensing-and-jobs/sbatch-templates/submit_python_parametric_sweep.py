#!/usr/bin/env python3
"""
Sim2GCP — Automated Python Parametric Sweep Submitter for Slurm
File: 4-licensing-and-jobs/sbatch-templates/submit_python_parametric_sweep.py

Description:
  Demonstrates how engineering teams can submit a batch of parametric CFD/FEA
  simulations to Slurm from Python. Slurm automatically scales the C3/H3
  compute nodes up from 0, runs the jobs in parallel (up to license/quota limits),
  and scales the cluster back down to 0 nodes (0 $/h) once finished.
"""

import argparse
import os
import re
import subprocess
from pathlib import Path


SAFE_CASE_RE = re.compile(r"^[a-zA-Z0-9_.-]{1,64}$")
SAFE_PARTITION_RE = re.compile(r"^[a-z][a-z0-9]{0,31}$")


def submit_case(case_name: str, partition: str, nodes: int, tasks_per_node: int, dry_run: bool) -> str:
    if not SAFE_CASE_RE.match(case_name):
        raise ValueError(f"Invalid case name: {case_name}")
    if not SAFE_PARTITION_RE.match(partition):
        raise ValueError(f"Invalid partition name: {partition}")
    if nodes < 1 or nodes > 128 or tasks_per_node < 1 or tasks_per_node > 192:
        raise ValueError("Node or task count out of allowed bounds.")

    case_dir = Path.home() / "simulations" / case_name
    case_dir.mkdir(parents=True, exist_ok=True)
    job_script = case_dir / f"run_{case_name}.sbatch"

    script_content = f"""#!/bin/bash
#SBATCH --job-name=sim_{case_name}
#SBATCH --partition={partition}
#SBATCH --nodes={nodes}
#SBATCH --ntasks-per-node={tasks_per_node}
#SBATCH --exclusive
#SBATCH --output={case_dir}/slurm_%j.out

set -euo pipefail
echo "Running case {case_name} on $((SLURM_NNODES * SLURM_NTASKS_PER_NODE)) physical cores..."
# Replace with your solver command (e.g., fluent, simpleFoam, abaqus)
srun hostname
"""
    job_script.write_text(script_content, encoding="utf-8")

    cmd = ["/usr/bin/sbatch", "--parsable", str(job_script)]
    if dry_run:
        print(f"[DRY-RUN] Generated {job_script} -> would execute: {' '.join(cmd)}")
        return "DRY_RUN_JOB_ID"

    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    job_id = proc.stdout.strip()
    print(f"Submitted {case_name} -> Slurm Job ID: {job_id}")
    return job_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Submit a parametric sweep of CAE jobs to Slurm.")
    parser.add_argument("--cases", nargs="+", default=["reynolds_1e5", "reynolds_5e5", "reynolds_1e6"], help="List of parametric case identifiers")
    parser.add_argument("--partition", default="cfdspot", help="Slurm partition (e.g., cfd or cfdspot)")
    parser.add_argument("--nodes", type=int, default=6, help="Compute nodes per case (default: 6 x c3-standard-88 = 264 physical cores)")
    parser.add_argument("--tasks-per-node", type=int, default=44, help="Physical cores per node (default: 44 for c3-standard-88)")
    parser.add_argument("--dry-run", action="store_true", help="Generate sbatch scripts without calling sbatch")
    args = parser.parse_args()

    for case_id in args.cases:
        submit_case(
            case_name=case_id,
            partition=args.partition,
            nodes=args.nodes,
            tasks_per_node=args.tasks_per_node,
            dry_run=args.dry_run,
        )


if __name__ == "__main__":
    main()
