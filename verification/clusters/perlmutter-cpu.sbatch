#!/bin/bash
# Release verification, CPU part, on TWO Perlmutter CPU nodes: no GPU is requested and the
# container starts without --gpu. First the 2-node MPICH step (one rank per node, over the
# fabric), then the job shrinks to its first node and runs verification/verify.py there.
#
# Usage (env.sh sourced: its sbatch function adds the account):
#   sbatch ~/idrobolab-env/verification/clusters/perlmutter-cpu.sbatch <image> [--only <component>]
#
# The image is ghcr.io/idrobolab/<image>:<VERSION>-rc, VERSION from the image's recipe
# directory. IMAGE overrides it: a bare name takes IMAGE_OWNER and TAG (default <VERSION>-rc),
# a value containing "/" is used verbatim. Pull it on a login node first:
#   TAG=<VERSION>-rc ~/idrobolab-env/perlmutter/helpers/update-image.sh <image>
# Records and logs are written into this clone, under verification/<image>/releases/<N>/.
# The time limit below is a guess for GPAW's full suite (tests/gpaw, the longest component):
# override it at submission, e.g.  sbatch --time=12:00:00 ... perlmutter-cpu.sbatch <image>
#
#SBATCH --job-name=verify_cpu
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=2
#SBATCH --cpus-per-task=256
#SBATCH --mem=440G
#SBATCH --time=04:00:00
#SBATCH --licenses=scratch,cfs
#SBATCH --output=%x_%j.out

set -euo pipefail

NAME=${1:?usage: sbatch perlmutter-cpu.sbatch <image> [--only <component>]}
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
VERIFY_IMAGE_DIGEST=$(podman-hpc images --digests --format '{{.Digest}}' "$IMAGE")
if [ -z "$VERIFY_IMAGE_DIGEST" ]; then
    echo "ERROR: $IMAGE is not in podman-hpc images; pull it first (header of this script)" >&2
    exit 1
fi
export VERIFY_IMAGE_DIGEST
export VERIFY_SCRUB="$USER:$HOME:$(real "$HOME"):$SCRATCH:$(real "$SCRATCH"):${CFS:-}:${SLURM_JOB_ACCOUNT:-}:${NERSC_PROJECT:-}:$REPO:$WORK"

# The 2-node MPICH step: one rank on each node, with the host Cray MPICH swapped in by --mpi
# (as in perlmutter/jobs/gpaw_cpu_multinode.sbatch). tests/mpich reports its exit status and
# log from VERIFY_MPI_STEP. A failure is recorded there, and does not stop the job; a hang in
# the fabric or in PMI ends after MPI_STEP_TIMEOUT seconds (10 minutes) with status 124.
STEP=$WORK/mpi-step
mkdir -p "$STEP"
STEP_STATUS=0
timeout --kill-after=30 "${MPI_STEP_TIMEOUT:-600}" \
    srun --nodes=2 --ntasks=2 --ntasks-per-node=1 --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS --mpi --network=no_vni -v "$REPO:$REPO" --workdir "$REPO" \
        "$IMAGE" python verification/tests/mpich --ring --ranks 2 > "$STEP/log" 2>&1 \
    || STEP_STATUS=$?
echo "$STEP_STATUS" > "$STEP/status"
echo "2-node MPICH step: exit status $STEP_STATUS"
cat "$STEP/log"
export VERIFY_MPI_STEP=$STEP

# The rest runs on the first node only: hand the second back, so it is not billed for the
# hours verify.py takes. scontrol writes a script that resets the SLURM_* variables to the
# smaller job, into the working directory. A refused shrink only costs the second node. The
# header sets no --ntasks-per-node, as on Delta, where it makes scontrol refuse the shrink.
if (cd "$WORK" && scontrol update JobId="$SLURM_JOB_ID" NumNodes=1); then
    . "$WORK/slurm_job_${SLURM_JOB_ID}_resize.sh"
    echo "released the second node: running on $SLURM_JOB_NODELIST"
else
    echo "WARNING: scontrol could not shrink the job; the second node stays allocated" >&2
fi

# OMP_NUM_THREADS and OPENBLAS_NUM_THREADS stay at the image's 1: with more, GPAW warns in
# PW mode and abTEM's suite turns the warning into an error. HDF5 file locking fails on CFS
# and $HOME from a compute node (errno 524).
time srun --nodes=1 --ntasks=1 --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS -v "$REPO:$REPO" -v "$GIT_COMMON:$GIT_COMMON" \
        -v "$WORK:$WORK" --workdir "$REPO" \
        -e VERIFY_CLUSTER -e VERIFY_IMAGE_DIGEST -e VERIFY_JOB_ID -e VERIFY_SCRUB -e VERIFY_WORK \
        -e VERIFY_MPI_STEP -e HDF5_USE_FILE_LOCKING=FALSE \
        "$IMAGE" python verification/verify.py "$NAME" --part cpu "$@"
