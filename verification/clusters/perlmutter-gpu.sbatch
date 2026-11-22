#!/bin/bash
# Release verification, GPU part, on ONE Perlmutter GPU node (4x A100): the
# container starts with --gpu. Runs verification/verify.py inside the image.
#
# Usage (env.sh sourced: its sbatch function adds the account):
#   sbatch ~/idrobolab-env/verification/clusters/perlmutter-gpu.sbatch <image> [--only <component>]
#
# The image is ghcr.io/idrobolab/<image>:<VERSION>-rc, VERSION from the image's recipe
# directory. IMAGE overrides it: a bare name takes IMAGE_OWNER and TAG (default <VERSION>-rc),
# a value containing "/" is used verbatim. Pull it on a login node first:
#   TAG=<VERSION>-rc ~/idrobolab-env/perlmutter/helpers/update-image.sh <image>
# Records and logs are written into this clone, under verification/<image>/releases/<N>/.
#
#SBATCH --job-name=verify_gpu
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=gpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none                # all 4 GPUs visible to the one task
#SBATCH --exclusive
#SBATCH --mem=220G
#SBATCH --time=04:00:00
#SBATCH --licenses=scratch,cfs
#SBATCH --output=%x_%j.out

set -euo pipefail

NAME=${1:?usage: sbatch perlmutter-gpu.sbatch <image> [--only <component>]}
shift

# Under sbatch, Slurm runs a spool copy of this script: find the original through the job.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
if [ ! -f "$REPO/verification/verify.py" ]; then
    SCRIPT=$(scontrol show job "$SLURM_JOB_ID" | sed -n 's/^ *Command=\([^ ]*\).*/\1/p')
    REPO=$(cd "$(dirname "$SCRIPT")/../.." && pwd -P)
fi
VERSION_FILES=("$REPO"/shared/containers/*/"$NAME"/VERSION)
if [ "${#VERSION_FILES[@]}" -ne 1 ] || [ ! -f "${VERSION_FILES[0]}" ]; then
    echo "ERROR: exactly one recipe directory shared/containers/*/$NAME is expected" >&2
    exit 1
fi
VERSION=$(cat "${VERSION_FILES[0]}")
IMAGE=${IMAGE:-$NAME}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-idrobolab}/${IMAGE}:${TAG:-${VERSION}-rc}" ;;
esac

# verify.py hashes its tests with git, which needs the repository's git directory: outside
# $REPO when the clone is a worktree (podman-hpc binds only what -v names).
GIT_COMMON=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)

# Supplementary groups give access to project directories; see jobs/README.md.
GROUP_FLAGS=${PODMAN_GROUP_FLAGS---group-add keep-groups}

# A writable work directory for the tests, removed at the end.
WORK=${SCRATCH:?}/verify-$SLURM_JOB_ID
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

# What only the host knows. VERIFY_SCRUB: strings verify.py removes from everything it writes.
real() { (cd "$1" 2>/dev/null && pwd -P) || true; }
export VERIFY_CLUSTER=perlmutter VERIFY_JOB_ID=$SLURM_JOB_ID VERIFY_WORK=$WORK
echo "IMAGE=$IMAGE  repo=$REPO"
# `podman-hpc images` lists the images of the shared read-only store; `image inspect` does not.
# `images` lists an image once per store that holds it; `sort -u` folds those lines.
VERIFY_IMAGE_DIGEST=$(podman-hpc images --digests --format '{{.Digest}}' "$IMAGE" | sort -u)
if [ -z "$VERIFY_IMAGE_DIGEST" ]; then
    echo "ERROR: $IMAGE is not in podman-hpc images; pull it first (header of this script)" >&2
    exit 1
fi
# Each store has its own tags: a stale copy in another store (podman-hpc's default squash
# directory, $SCRATCH/storage, after a plain `podman-hpc pull`) keeps the tag, and podman
# may run either image.
if [ "$(printf '%s\n' "$VERIFY_IMAGE_DIGEST" | wc -l)" -gt 1 ]; then
    echo "ERROR: $IMAGE names several images:" $VERIFY_IMAGE_DIGEST >&2
    echo "  remove the unwanted copy from its store (\$SCRATCH/storage or \$PODMAN_STORE):" >&2
    echo "  podman-hpc --squash-dir <store> rmsqi $IMAGE" >&2
    exit 1
fi
export VERIFY_IMAGE_DIGEST
export VERIFY_SCRUB="$USER:$HOME:$(real "$HOME"):$SCRATCH:$(real "$SCRATCH"):${CFS:-}:${SLURM_JOB_ACCOUNT:-}:${NERSC_PROJECT:-}:$REPO:$WORK"

# The job's end time (epoch seconds), so verify.py stops its components in time to write the
# record. When squeue or date fails, or the time is unknown, verify.py runs without a deadline.
if END=$(squeue -h -j "$SLURM_JOB_ID" -o %e 2>/dev/null) && [ -n "$END" ] \
        && DEADLINE=$(date -d "$END" +%s 2>/dev/null); then
    export VERIFY_DEADLINE=$DEADLINE
fi

# OMP_NUM_THREADS and OPENBLAS_NUM_THREADS stay at the image's 1: with more, GPAW warns in
# PW mode and abTEM's suite turns the warning into an error. HDF5 file locking fails on CFS
# and $HOME from a compute node (errno 524).
time srun --ntasks=1 --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS --gpu -v "$REPO:$REPO" -v "$GIT_COMMON:$GIT_COMMON" \
        -v "$WORK:$WORK" --workdir "$REPO" \
        -e VERIFY_CLUSTER -e VERIFY_IMAGE_DIGEST -e VERIFY_JOB_ID -e VERIFY_SCRUB -e VERIFY_WORK \
        -e VERIFY_DEADLINE -e HDF5_USE_FILE_LOCKING=FALSE \
        "$IMAGE" python verification/verify.py "$NAME" --part gpu "$@"
