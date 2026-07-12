#!/bin/bash
# Full quad-A100 node (gpuA100x4): GPU Python workloads — abTEM multislice,
# orb-models, torch/jax — from another image's container.
# Charging: 1 A100-hour = 16 core-hours = 62.5 GB-hours (whichever is larger).
#
# Usage:  sbatch gpu_a100x4.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_a100x4
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts` command
#SBATCH --partition=gpuA100x4
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1             # single python process driving 4 GPUs
#SBATCH --cpus-per-task=64
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=closest              # cpu close to gpu on pci bus topology
#SBATCH --mem=208G                      # NCSA's full-node sample value
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, sets $WORK/$SCRATCH; before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif}
SCRIPT=${1:?usage: sbatch gpu_a100x4.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

# Run a cluster checkout instead of the baked-in code:
# BINDS="$BINDS,$SCRATCH/code/otherimage:/opt/src/otherimage"

# For 4 MPI ranks x 1 GPU each (instead of one process using 4 GPUs), switch
# the payload to:  mpiexec -n 4 python "$SCRIPT" "$@"
# and set --ntasks-per-node=1 --cpus-per-task=64 as-is (hydra spawns inside).

echo "SIF=$SIF  binds=$BINDS  CUDA_VISIBLE_DEVICES on node: 0-3"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
