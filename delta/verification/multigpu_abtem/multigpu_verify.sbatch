#!/bin/bash
# Multi-GPU verification for abTEM on Delta's gpuA100x4 partition.
# Runs verify_multigpu.py inside another image's container (which now ships
# dask-cuda), using an overlay venv (built once by setup_env.sh) that layers
# the abTEM 'multi-gpu-support' branch over the container's abTEM 1.0.9.
#
# Usage:
#   # once (no internet needed with a local abTEM checkout):
#   ABTEM_SRC=$SCRATCH/code/abTEM ./setup_env.sh
#   # then:
#   sbatch multigpu_verify.sbatch                 # 4 GPUs, default checks
#   sbatch multigpu_verify.sbatch --timing        # add 1-vs-N GPU timing
#
# For 8 GPUs switch the partition/resources below to the gpuA100x8 block, or
# copy this file. Charging: 1 A100-hour = 16 core-hours = 62.5 GB-hours.
#
#SBATCH --job-name=abtem_mgpu
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts`
#SBATCH --partition=gpuA100x4
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1             # one python process driving all GPUs
#SBATCH --cpus-per-task=64
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=closest
#SBATCH --mem=208G
#SBATCH --time=00:30:00
#SBATCH --constraint="scratch"
#SBATCH --output=%x_%j.out
#
# --- 8-GPU variant: comment the four lines above marked (4x) and use ------
# #SBATCH --partition=gpuA100x8
# #SBATCH --cpus-per-task=128
# #SBATCH --gpus-per-node=8
# #SBATCH --mem=0
# --------------------------------------------------------------------------

module reset   # loads defaults, sets $WORK/$SCRATCH; before set -u (Lmod quirk)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIF=${SIF:-${SCRATCH:?set SIF, or run where 'module reset' exports SCRATCH}/containers/otherimage_delta.sif}
# abTEM 'multi-gpu-support' checkout. It is injected via PYTHONPATH to shadow the
# container's abTEM 1.0.9 -- no venv: the container is read-only and its Python is
# itself a venv, so a nested venv cannot see the container's dask-cuda/cupy.
ABTEM_SRC=${ABTEM_SRC:-$SCRATCH/code/abTEM}

if [ ! -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    echo "ERROR: abTEM checkout not found at $ABTEM_SRC" >&2
    echo "Set ABTEM_SRC to your 'multi-gpu-support' checkout." >&2
    exit 1
fi

BINDS="$HERE"
for p in /projects /scratch /work "$ABTEM_SRC"; do
    [ -e "$p" ] && BINDS="${BINDS:+$BINDS,}$p"
done

echo "SIF=$SIF"
echo "abtem_src=$ABTEM_SRC (via PYTHONPATH)"
echo "GPUs requested: ${SLURM_GPUS_ON_NODE:-?}   node=$(hostname)"

# --nv exposes the GPUs; PYTHONPATH makes the container Python import the branch
# abTEM while dask-cuda/cupy/dask come from the container.
time APPTAINERENV_PYTHONPATH="$ABTEM_SRC" apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$HERE/verify_multigpu.py" "$@"
