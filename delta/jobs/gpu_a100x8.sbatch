#!/bin/bash
# Full 8-way A100 large-memory node (gpuA100x8: 8x A100 40GB, 128 cores,
# 2 TB RAM, charge factor 1.5) — for jobs needing many GPUs on one node or
# the 2 TB of host memory. Charging: 1 GPU-hour = 16 core-hours = 250 GB-hours.
#
# Usage:  sbatch gpu_a100x8.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_a100x8
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts` command
#SBATCH --partition=gpuA100x8
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --gpus-per-node=8
#SBATCH --gpu-bind=closest
#SBATCH --exclusive
#SBATCH --mem=1760G                    # 8x A100 node, ~2 TB (~86% as with 220G/256G)
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, sets $WORK/$SCRATCH_BASE (no $SCRATCH on Delta!); before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif}
SCRIPT=${1:?usage: sbatch gpu_a100x8.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

echo "SIF=$SIF  binds=$BINDS"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
