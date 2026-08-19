#!/bin/bash
# Single A100 on a SHARED GPU node — the cheapest way to run GPU work on
# Perlmutter and the right default for development, single-GPU abTEM
# multislice, orb-models relaxations, and anything that fits in 40 GB.
#
# NERSC policy: jobs needing only 1 or 2 GPUs SHOULD use the shared QOS.
# A shared job is charged only for the fraction of the node it holds:
#   1 GPU -> 16 physical cores + 64 GB -> 0.25 node-hour per wallclock hour
#   2 GPU -> 32 physical cores + 128 GB -> 0.5  node-hour per wallclock hour
# Max walltime 48 h, max half a node.
#
# Usage:  sbatch gpu_1gpu_shared.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_1gpu
#SBATCH --account=<project>_g          # <- replace; GPU vs CPU accounts differ, verify with sacctmgr (README)
#SBATCH --constraint=gpu
#SBATCH --qos=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32             # 32 logical = 16 physical cores
#SBATCH --gpus=1
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=%x_%j.out

set -euo pipefail

# Preserve supplementary group membership inside the container. podman runs
# rootless in a user namespace, and by default only the PRIMARY group is mapped:
# every supplementary group -- which on NERSC is how project access to
# /global/cfs/cdirs/<project> is granted -- is dropped. The symptom is a path
# your shell can enter but the container cannot:
#
#   Error: crun: chdir to `/global/cfs/cdirs/<project>/...`: Permission denied
#
# It bites collaborators for whom the project group is supplementary while
# working fine for whoever has it as their primary group, which makes it look
# like a per-user permission problem. `keep-groups` (crun only, rootless only)
# passes them through. Set PODMAN_GROUP_FLAGS= to disable if it ever misbehaves.
GROUP_FLAGS=${PODMAN_GROUP_FLAGS---group-add keep-groups}

# Image. Accepts a bare name -- IMAGE=otherimage -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-<username>}/${IMAGE}:${TAG:-latest}" ;;
esac
SCRIPT=${1:?usage: sbatch gpu_1gpu_shared.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code:
# MOUNTS="$MOUNTS -v $SCRATCH/code/otherimage:/opt/src/otherimage"

# Single process, no MPI launcher -> GPAW_MPI_BACKEND is not needed here.
# Give the one process the threads it paid for (16 physical cores).
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

echo "IMAGE=$IMAGE  gpus=1  mounts=$MOUNTS"
time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $THREAD_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# For 2 GPUs in the same QOS: --gpus=2 --cpus-per-task=64 --mem=128G
# (still one process; let the code see both devices).
