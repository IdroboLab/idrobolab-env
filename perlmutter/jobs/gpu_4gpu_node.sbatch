#!/bin/bash
# Full quad-A100 GPU node (exclusive): one Python process driving all 4 GPUs.
# For abTEM multi-GPU dask scheduling, torch/jax multi-device work, or any
# job that needs the whole node's 256 GB host RAM.
#
# Node: 1x AMD EPYC 7763 (Milan), 64 physical cores (128 logical), 256 GB DDR4,
#       4x A100 40 GB HBM2 (NVLink3, 4 links per GPU pair), 4x Slingshot-11.
# Charging: walltime x 1 node x 1.0 — i.e. 4x what the shared 1-GPU script
# costs per hour. Use gpu_1gpu_shared.sbatch unless you really need 4 GPUs.
#
# Usage:  sbatch gpu_4gpu_node.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_4gpu
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1            # single process, 4 visible GPUs
#SBATCH --cpus-per-task=128            # all logical CPUs on the node
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none                # all 4 GPUs visible to the one task
#SBATCH --exclusive
#SBATCH --mem=220G                     # full 256 GB GPU node
#SBATCH --time=02:00:00
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
SCRIPT=${1:?usage: sbatch gpu_4gpu_node.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code:
# MOUNTS="$MOUNTS -v $SCRATCH/code/abTEM:/opt/src/abTEM"

# One process, 4 GPUs: leave room for the CUDA/dask worker threads rather
# than pinning everything to one thread.
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

echo "IMAGE=$IMAGE  gpus=4  mounts=$MOUNTS"
time srun --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $THREAD_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# For 4 MPI ranks x 1 GPU each on this node instead of one 4-GPU process, use
# gpu_multinode_mpi.sbatch with --nodes=1 — it has the rank/GPU binding set up.
