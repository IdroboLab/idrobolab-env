#!/bin/bash
# Release verification, CPU part, on ONE Delta CPU node: no GPU is requested and Apptainer
# runs without --nv. Runs verification/verify.py inside the image.
#
# Usage (env.sh sourced: its sbatch function adds the account):
#   sbatch ~/idrobolab-env/verification/clusters/delta-cpu.sbatch <image> [--only <component>]
#
# SIF defaults to $PROJECTS_BASE/software/containers/<image>.sif; build it from the release
# candidate first:  TAG=<VERSION>-rc SIF=$PROJECTS_BASE/software/containers/<image>.sif ~/idrobolab-env/delta/get-image.sh
# Records and logs are written into this clone, under verification/<image>/releases/<N>/.
#
#SBATCH --job-name=verify_cpu
#SBATCH --account=<project>-delta-cpu   # <- replace; see `accounts` command
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=240G
#SBATCH --time=04:00:00
#SBATCH --constraint="scratch&projects" # filesystem dependency (NCSA-requested)
#SBATCH --output=%x_%j.out

module reset   # loads defaults, $SCRATCH_BASE comes from delta/env.sh (Delta sets $SCRATCH only inside jobs); before set -u (Lmod quirk)
set -euo pipefail

NAME=${1:?usage: sbatch delta-cpu.sbatch <image> [--only <component>]}
shift

# Under sbatch, Slurm runs a spool copy of this script: find the original through the job.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
if [ ! -f "$REPO/verification/verify.py" ]; then
    SCRIPT=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/^ *Command=\([^ ]*\).*/\1/p')
    REPO=$(cd "$(dirname "$SCRIPT")/../.." && pwd -P)
fi
SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/${NAME}.sif}

# A writable work directory for the tests, removed at the end.
WORK=${SCRATCH_BASE:?}/$USER/verify-$SLURM_JOB_ID
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

BINDS="$REPO,$WORK"
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="$BINDS,$p"; done

# What only the host knows. VERIFY_SCRUB: strings verify.py removes from everything it writes.
# Apptainer passes the host environment into the container.
real() { (cd "$1" 2>/dev/null && pwd -P) || true; }
export VERIFY_CLUSTER=delta VERIFY_JOB_ID=$SLURM_JOB_ID VERIFY_WORK=$WORK
# Numba caches compiled functions next to their source, inside the small --writable-tmpfs
# layer; a full layer fails the tests with ENOSPC. The cache goes to the work directory.
export NUMBA_CACHE_DIR=$WORK/numba
VERIFY_IMAGE_DIGEST=$(sha256sum "$SIF")
export VERIFY_IMAGE_DIGEST=sha256:${VERIFY_IMAGE_DIGEST%% *}
export VERIFY_SCRUB="$USER:$HOME:$(real "$HOME"):$SCRATCH_BASE/$USER:$(real "$SCRATCH_BASE/$USER"):${PROJECTS_BASE:-}:${SLURM_JOB_ACCOUNT:-}:$REPO:$WORK"

echo "SIF=$SIF  repo=$REPO  binds=$BINDS"
# --writable-tmpfs: run_pytest.py installs test dependencies into the image's /opt/venv,
# which a .sif mounts read-only; the writable layer is discarded at exit.
time apptainer exec --writable-tmpfs --bind "$BINDS" --pwd "$REPO" "$SIF" \
    python verification/verify.py "$NAME" --part cpu "$@"
