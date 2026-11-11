#!/bin/bash
# Full quad-A100 node (gpuA100x4): GPU Python workloads — abTEM multislice,
# orb-models, torch, cupy — from the idrobolab container.
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
#SBATCH --mem=220G                     # full 256 GB A100 node
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch&projects"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, $SCRATCH_BASE comes from delta/env.sh (no $SCRATCH on Delta!); before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif}
SCRIPT=${1:?usage: sbatch gpu_a100x4.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

# Run a cluster checkout instead of the baked-in code:
# BINDS="$BINDS,<project-dir>/code/gpaw:/opt/src/gpaw"

# For 4 MPI ranks x 1 GPU each (instead of one process using 4 GPUs), switch
# the payload to:  mpiexec -bootstrap fork -n 4 python "$SCRIPT" "$@"
# (-bootstrap fork is required so Hydra spawns ranks locally instead of via
#  the host `srun`, which is absent inside the container)
# and set --ntasks-per-node=1 --cpus-per-task=64 as-is (hydra spawns inside).
# That payload ALSO needs `export GPAW_MPI_BACKEND=cgpaw` if the script uses
# GPAW: 26.7.0+ aborts at import under an MPI launcher otherwise (see
# gpaw_cpu_singlenode.sbatch). Not needed for the single-process form below —
# without a launcher no PMI_SIZE is exported and the check stays quiet.

echo "SIF=$SIF  binds=$BINDS  CUDA_VISIBLE_DEVICES on node: 0-3"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
