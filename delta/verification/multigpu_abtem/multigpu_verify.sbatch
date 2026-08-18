#!/bin/bash
# Multi-GPU verification for abTEM on Delta's gpuA100x4 partition.
# Runs verify_multigpu.py inside another image's container (which ships
# dask-cuda), with the abTEM 'multi-gpu-support' branch injected via PYTHONPATH
# to shadow the container's own abTEM (no venv). NB: the image installs abTEM
# editable from a staged checkout, so its version is NOT a reliable way to tell
# container from branch -- both currently report 1.1.0. Only abtem.__file__ is.
#
# Usage:
#   SIF=/path/otherimage_delta.sif ABTEM_SRC=/path/abTEM \
#     sbatch multigpu_verify.sbatch            # 4 GPUs, default checks
#   (add --timing for a 1-vs-N GPU wall-clock comparison)
#   # optional preflight (no venv):  ABTEM_SRC=/path/abTEM ./setup_env.sh
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
#SBATCH --exclusive
#SBATCH --mem=220G                     # full 256 GB A100 node
#SBATCH --time=00:10:00
#SBATCH --constraint="scratch&projects"
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

# Under `sbatch`, Slurm runs a spool COPY of this script, so BASH_SOURCE points
# at the spool dir (payload absent). Use the submit dir; fall back to the script
# dir for `bash` runs. Submit from the directory holding verify_multigpu.py.
HERE="${SLURM_SUBMIT_DIR:-}"
[ -n "$HERE" ] || HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python payloads are shared with Perlmutter and live in
# shared/verification/multigpu_abtem/; only the launchers are per-cluster, so
# the two clusters cannot drift. Resolved relative to this directory; override
# with PAYLOAD_DIR if you keep the payloads elsewhere.
PAYLOAD_DIR=${PAYLOAD_DIR:-$HERE/../../../shared/verification/multigpu_abtem}
if [ -d "$PAYLOAD_DIR" ]; then
    PAYLOAD_DIR=$(cd "$PAYLOAD_DIR" && pwd)
fi
if [ ! -f "$PAYLOAD_DIR/verify_multigpu.py" ]; then
    echo "ERROR: verify_multigpu.py not found in $PAYLOAD_DIR" >&2
    exit 1
fi

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif}
# abTEM 'multi-gpu-support' checkout. It is injected via PYTHONPATH to shadow the
# container's own abTEM -- no venv: the container is read-only and its Python is
# itself a venv, so a nested venv cannot see the container's dask-cuda/cupy.
ABTEM_SRC=${ABTEM_SRC:-$SCRATCH/code/abTEM}

if [ ! -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    echo "ERROR: abTEM checkout not found at $ABTEM_SRC" >&2
    echo "Set ABTEM_SRC to your 'multi-gpu-support' checkout." >&2
    exit 1
fi

BINDS="$HERE,$PAYLOAD_DIR"
for p in /projects /scratch /work "$ABTEM_SRC"; do
    [ -e "$p" ] && BINDS="${BINDS:+$BINDS,}$p"
done

echo "SIF=$SIF"
echo "abtem_src=$ABTEM_SRC (via PYTHONPATH)"
echo "GPUs requested: ${SLURM_GPUS_ON_NODE:-?}   node=$(hostname)"

# --nv exposes the GPUs; PYTHONPATH makes the container Python import the branch
# abTEM while dask-cuda/cupy/dask come from the container.
time APPTAINERENV_PYTHONPATH="$ABTEM_SRC" apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$PAYLOAD_DIR/verify_multigpu.py" "$@"
