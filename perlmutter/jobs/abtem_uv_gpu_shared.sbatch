#!/bin/bash
# abTEM from your own uv environment (~/venvs/abtem, not the container) on 1 or
# 2 A100s of a SHARED GPU node. Use it when the container's abTEM (or another
# package) is not recent enough; the recipe for the environment is in
# docs/perlmutter/07-abtem.md. Otherwise the container templates (gpu_1gpu_shared.sbatch,
# gpu_2gpu_shared.sbatch) are the default.
#
# The job runs the environment's own python, never `uv run`: compute nodes should
# not download anything, and /global/common is read-only there. Create or
# update the environment on a login node.
#
# One process. With 2 GPUs it sees both (CuPy devices 0 and 1); a script has to
# pick its devices itself, and the example script uses device 0 only. ONE abTEM
# calculation spread over several GPUs needs dask-cuda, whose cuda-bindings
# dependency is fragile to resolve outside the container: run that as a
# container job (gpu_2gpu_shared.sbatch, gpu_4gpu_node.sbatch).
#
# Charging: 1 GPU -> 0.25 node-hour per wallclock hour, 2 GPUs -> 0.5.
#
# Usage:  sbatch abtem_uv_gpu_shared.sbatch my_script.py [args...]
#         sbatch abtem_uv_gpu_shared.sbatch ~/idrobolab-env/perlmutter/examples/abtem/abtem_gpu_example.py
#         sbatch --gpus=2 --cpus-per-task=64 abtem_uv_gpu_shared.sbatch my_script.py   # 2 GPUs
#         VENV=~/venvs/other sbatch abtem_uv_gpu_shared.sbatch my_script.py            # another environment
#
#SBATCH --job-name=abtem_uv
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu
#SBATCH --qos=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
# GPU COUNT: set these two lines together, the shared queue requires exactly 32
# logical cores per GPU. 1 GPU: --gpus=1 with -c 32. 2 GPUs: --gpus=2 with -c 64
# (not --gpus-per-task=2: the queue rejects that). No --mem, see
# gpu_1gpu_shared.sbatch.
#SBATCH --gpus=1
#SBATCH --cpus-per-task=32
#SBATCH --time=04:00:00
# File-system licenses: add #SBATCH --licenses=... for what your script uses (docs/perlmutter/04-jobs.md).
#SBATCH --output=%x_%j.out

set -euo pipefail

VENV=${VENV:-$HOME/venvs/abtem}
SCRIPT=${1:?usage: sbatch abtem_uv_gpu_shared.sbatch script.py [args]}
shift
[ -x "$VENV/bin/python" ] || { echo "no environment at $VENV: create it as described in docs/perlmutter/07-abtem.md" >&2; exit 1; }

# One process: the threads it paid for (2 logical CPUs per physical core).
export OMP_NUM_THREADS=$((SLURM_CPUS_PER_TASK / 2)) OPENBLAS_NUM_THREADS=$((SLURM_CPUS_PER_TASK / 2))
export PYTHONUNBUFFERED=1

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
export HDF5_USE_FILE_LOCKING=FALSE

echo "python=$VENV/bin/python  gpus=${SLURM_GPUS:-?}  script=$SCRIPT"
time srun -c "$SLURM_CPUS_PER_TASK" --cpu-bind=cores "$VENV/bin/python" "$SCRIPT" "$@"
