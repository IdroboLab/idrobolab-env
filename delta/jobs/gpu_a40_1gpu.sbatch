#!/bin/bash
# Single A40 on a shared gpuA40x4 node — cheapest NVIDIA GPU on Delta
# (charge factor 0.5): development, light CUDA work, visualization-adjacent
# jobs. A40 = sm_86, 48 GB, PCIe (no NVLink), weak FP64 — do NOT use for
# the complex128/FP64-heavy production runs.
#
# Usage:  sbatch gpu_a40_1gpu.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_a40
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts` command
#SBATCH --partition=gpuA40x4
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --gpu-bind=closest
#SBATCH --mem=50G                      # NCSA's 1-A40 sample value
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch&projects"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, $SCRATCH_BASE comes from delta/env.sh (no $SCRATCH on Delta!); before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif}
SCRIPT=${1:?usage: sbatch gpu_a40_1gpu.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

echo "SIF=$SIF  binds=$BINDS"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
