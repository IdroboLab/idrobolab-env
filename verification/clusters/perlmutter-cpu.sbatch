#!/bin/bash
# Release verification, CPU part, on ONE Perlmutter CPU node: no GPU is requested and the
# container starts without --gpu. Runs verification/verify.py inside the image.
#
# Usage (env.sh sourced: its sbatch function adds the account):
#   sbatch ~/idrobolab-env/verification/clusters/perlmutter-cpu.sbatch <image> [--only <component>]
#
# The image is ghcr.io/idrobolab/<image>:<VERSION>-rc, VERSION from the image's recipe
# directory. IMAGE overrides it: a bare name takes IMAGE_OWNER and TAG (default <VERSION>-rc),
# a value containing "/" is used verbatim. Pull it on a login node first:
#   TAG=<VERSION>-rc ~/idrobolab-env/perlmutter/helpers/update-image.sh <image>
# Records and logs are written into this clone, under verification/<image>/releases/<N>/.
#
#SBATCH --job-name=verify_cpu
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
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
VERIFY_IMAGE_DIGEST=$(podman-hpc image inspect --format '{{index .RepoDigests 0}}' "$IMAGE")
export VERIFY_IMAGE_DIGEST=${VERIFY_IMAGE_DIGEST##*@}
export VERIFY_SCRUB="$USER:$HOME:$(real "$HOME"):$SCRATCH:$(real "$SCRATCH"):${CFS:-}:${SLURM_JOB_ACCOUNT:-}:${NERSC_PROJECT:-}:$REPO:$WORK"

echo "IMAGE=$IMAGE  repo=$REPO"
# One process: leave room for worker threads rather than pinning to one thread (see
# jobs/gpu_4gpu_node.sbatch). HDF5 file locking fails on CFS and $HOME from a compute node
# (errno 524).
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"
time srun --ntasks=1 --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS -v "$REPO:$REPO" -v "$WORK:$WORK" --workdir "$REPO" \
        -e VERIFY_CLUSTER -e VERIFY_IMAGE_DIGEST -e VERIFY_JOB_ID -e VERIFY_SCRUB -e VERIFY_WORK \
        $THREAD_ENV -e HDF5_USE_FILE_LOCKING=FALSE \
        "$IMAGE" python verification/verify.py "$NAME" --part cpu "$@"
