#!/bin/bash
# Full H200 node (gpuH200x8: 8x H200 141GB SXM/NVLink, 2x Intel Xeon 8558 =
# 96 cores, 2 TB RAM; the only Intel nodes on Delta; max 1 node/job; charge
# factor 3.0) — the FP64/large-memory flagship partition: complex128 EMCD
# runs, exact-S2 / large-crop asymmetry-gate jobs.
# Charging: 1 H200-hour = 12 core-hours = 250 GB-hours.
# H200 = sm_90: covered by the image's Python wheels (torch cu129, cupy) and
# MAGMA (Ampere + Hopper); its QE GPU build targets sm_80 and LAMMPS is built
# for AMPERE80 (PTX JIT on Hopper).
#
# Usage:  sbatch gpu_h200x8.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_h200
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts` command
#SBATCH --partition=gpuH200x8
#SBATCH --nodes=1                       # partition maximum is 1 node/job
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=96
#SBATCH --gpus-per-node=8
#SBATCH --gpu-bind=closest
#SBATCH --exclusive
#SBATCH --mem=1760G                    # 8x H200 node, ~2 TB (~86% as with 220G/256G)
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch&projects"
#SBATCH --output=%x_%j.out

module reset   # loads defaults, $SCRATCH_BASE comes from delta/env.sh (no $SCRATCH on Delta!); before set -u (Lmod quirk)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif}
SCRIPT=${1:?usage: sbatch gpu_h200x8.sbatch script.py [args]}
shift

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

# Fewer GPUs (shared node): change --gpus-per-node, --cpus-per-task=12 per
# GPU, --mem=245G per GPU, and drop --exclusive/--mem=0.

echo "SIF=$SIF  binds=$BINDS"
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"
