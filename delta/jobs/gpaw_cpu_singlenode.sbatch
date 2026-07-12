#!/bin/bash
# GPAW / another image MPI job on ONE cpu-partition node, using the MPICH
# *inside* the container (mpiexec/hydra) — no host-MPI integration needed.
# This is the verified, zero-surprises way to run MPI GPAW up to one full
# node (128 ranks). For multi-node, see gpaw_cpu_multinode.sbatch.
#
# Usage:  sbatch gpaw_cpu_singlenode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_cpu
#SBATCH --account=<project>-delta-cpu   # <- replace; see `accounts` command
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1             # one apptainer launch; MPI ranks live inside
#SBATCH --cpus-per-task=64              # = MPI ranks used below (max 128/node)
#SBATCH --mem=124G                      # ~2 GB/rank; full node: --exclusive --mem=0
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch"          # filesystem dependency (NCSA-requested)
#SBATCH --output=%x_%j.out

module reset   # loads defaults (incl. cray-mpich), sets $WORK/$SCRATCH; before set -u (Lmod)
set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif}
SCRIPT=${1:?usage: sbatch gpaw_cpu_singlenode.sbatch script.py [args]}
shift

# Bind the shared filesystems that exist on this system ($HOME and $PWD are
# bound automatically by Apptainer).
BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

# Run a cluster checkout instead of the baked-in code (container README,
# "Running your own branches"):
# BINDS="$BINDS,$SCRATCH/code/gpaw:/opt/src/gpaw"

export OMP_NUM_THREADS=1                # pure MPI; the image defaults to 1 anyway

echo "SIF=$SIF  ranks=$SLURM_CPUS_PER_TASK  binds=$BINDS"
time apptainer exec --bind "$BINDS" "$SIF" \
    mpiexec -n "$SLURM_CPUS_PER_TASK" python "$SCRIPT" "$@"
