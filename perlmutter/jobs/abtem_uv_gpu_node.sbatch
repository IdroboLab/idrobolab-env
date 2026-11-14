#!/bin/bash
# Four INDEPENDENT single-GPU abTEM runs at once, one per A100 of a whole GPU
# node, from your own uv environment (~/venvs/abtem, not the container): a
# parameter sweep of four points. Use it only when all four GPUs stay busy; for
# 1-2 GPUs use abtem_uv_gpu_shared.sbatch (4x cheaper per GPU).
#
# Four tasks, each started by srun with one GPU of its own (--gpus-per-task=1).
# They differ by SLURM_PROCID (0..3), which the srun line below turns into the
# swept parameter and the output directory. The line is written for
# examples/abtem/abtem_gpu_example.py (--energy, --out): edit it for your script.
#
# ONE abTEM calculation spread over the four GPUs needs dask-cuda, whose
# cuda-bindings dependency is fragile to resolve outside the container: run that
# as a container job (gpu_4gpu_node.sbatch). Create or update ~/venvs/abtem on a
# login node (docs/perlmutter/07-abtem.md): compute nodes should not download anything, and
# /global/common is read-only there.
#
# Charging: walltime x 1 node x 1.0 (4x the 1-GPU shared job per hour).
#
# Usage:  sbatch -A "$NERSC_PROJECT" abtem_uv_gpu_node.sbatch my_script.py [args...]
#         sbatch -A "$NERSC_PROJECT" abtem_uv_gpu_node.sbatch ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py
#
#SBATCH --job-name=abtem_uv4
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=gpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4            # one task per GPU
#SBATCH --cpus-per-task=32             # 32 logical = 16 physical cores per task
#SBATCH --gpus-per-node=4
#SBATCH --exclusive
#SBATCH --mem=220G                     # full 256 GB GPU node
#SBATCH --time=02:00:00
# NERSC file-system licenses: see docs/perlmutter/04-jobs.md
#SBATCH --licenses=scratch
#SBATCH --output=%x_%j.out

set -euo pipefail

VENV=${VENV:-$HOME/venvs/abtem}
SCRIPT=${1:?usage: sbatch abtem_uv_gpu_node.sbatch script.py [args]}
shift
[ -x "$VENV/bin/python" ] || { echo "no environment at $VENV: create it as described in docs/perlmutter/07-abtem.md" >&2; exit 1; }
export OUT=${OUT:-${SCRATCH:?SCRATCH is not set}/abtem-sweep-$SLURM_JOB_ID}   # read by the srun line below

export OMP_NUM_THREADS=16 OPENBLAS_NUM_THREADS=16
export PYTHONUNBUFFERED=1

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
export HDF5_USE_FILE_LOCKING=FALSE

echo "python=$VENV/bin/python  script=$SCRIPT  out=$OUT"
# The sweep: task i runs the script at the i-th electron energy (keV; the work per
# task is the same) and writes to its own output directory.
time srun --ntasks=4 --cpus-per-task=32 --gpus-per-task=1 --cpu-bind=cores \
    bash -c 'energies=(60 100 150 200); energy=${energies[SLURM_PROCID]}
             exec "$@" --energy "$energy" --out "$OUT/energy${energy}keV"' \
    _ "$VENV/bin/python" "$SCRIPT" "$@"
