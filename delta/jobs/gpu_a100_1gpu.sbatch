#!/bin/bash
# Single A100 on a shared gpuA100x4 node — the cheap workhorse for GPU
# development runs, single-GPU abTEM/orb/torch jobs, and postprocessing.
# Charging: 1 A100-hour = 16 core-hours = 62.5 GB-hours (whichever is larger),
# so 16 cpus + 62G + 1 GPU is the "even" request.
#
# Usage:  sbatch gpu_a100_1gpu.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_a100
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts` command
#SBATCH --partition=gpuA100x4
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=16
#SBATCH --gpus-per-node=1
#SBATCH --gpu-bind=closest
#SBATCH --mem=62G
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, sets $WORK/$SCRATCH; before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${SCRATCH:?set SIF, or run where 'module reset' exports SCRATCH}/containers/otherimage_delta.sif}
SCRIPT=${1:?usage: sbatch gpu_a100_1gpu.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

echo "SIF=$SIF  binds=$BINDS"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
