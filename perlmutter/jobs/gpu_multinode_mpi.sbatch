#!/bin/bash
# Multi-node GPU MPI: 4 ranks per node, 1 A100 per rank. The pattern for
# GPU-parallel GPAW (GPAW_NEW=1 GPAW_USE_GPUS=1, parallel={'gpu': True}) and
# for distributed torch/jax work across nodes.
#
# Two things are stacked here that the single-node GPU scripts do not need:
#   --mpi        swaps the host Cray MPICH into the container (Slingshot)
#   --nccl-cu12  installs NERSC's Slingshot-tuned NCCL plugin (CUDA 12 image);
#                only matters for NCCL collectives (torch DDP), harmless
#                otherwise. Use --nccl-cu13 if the image ever moves to CUDA 13.
#
# Charging: walltime x nodes x 1.0. GPU jobs of 128+ nodes in the regular QOS
# get a 25% big-job discount (QOS factor 0.75).
#
# Usage:  sbatch gpu_multinode_mpi.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_gpumpi
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu
#SBATCH --qos=regular
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4            # 1 rank per GPU
#SBATCH --cpus-per-task=32             # 2 x floor(64/4) logical CPUs
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none                # see the binding note below
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
SCRIPT=${1:?usage: sbatch gpu_multinode_mpi.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code:
# MOUNTS="$MOUNTS -v $SCRATCH/code/gpaw:/opt/src/gpaw"

# Required for GPAW 26.7.0+ under an MPI launcher with plain `python`.
GPAW_ENV="-e GPAW_MPI_BACKEND=cgpaw -e OMP_NUM_THREADS=8"

MPICH_ENV="-e MPICH_SMP_SINGLE_COPY_MODE=CMA -e MPICH_GPU_SUPPORT_ENABLED=1"

# --- GPU binding ----------------------------------------------------------
# All 4 GPUs are left visible to every rank (--gpu-bind=none) and the rank
# picks its device from its node-local rank. This is the arrangement NERSC
# recommends for NCCL, and it is what GPAW's GPU backend and torch's
# LOCAL_RANK convention both expect. SLURM_LOCALID is passed through so the
# code inside the container can see it.
RANK_ENV="-e SLURM_LOCALID -e SLURM_PROCID -e SLURM_NTASKS"
# Alternative (one GPU visible per rank, chosen by Slurm): drop --gpu-bind
# from the #SBATCH block, use --gpus-per-task=1, and let CUDA_VISIBLE_DEVICES
# be set for you. Verify with the nvidia-smi step below before trusting it —
# how podman-hpc's --gpu module interacts with per-task binding is worth
# confirming on your first run.

echo "IMAGE=$IMAGE  nodes=$SLURM_JOB_NUM_NODES  ranks=$SLURM_NTASKS"
srun --cpu-bind=cores podman-hpc run --rm $GROUP_FLAGS --gpu $MOUNTS "$IMAGE" \
    bash -c 'echo "rank $SLURM_PROCID localid $SLURM_LOCALID sees $(nvidia-smi -L | wc -l) GPUs"' \
    || echo "(GPU visibility probe failed — check --gpu / binding)"

time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --mpi --gpu --nccl-cu12 --network=no_vni \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $GPAW_ENV $MPICH_ENV $RANK_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# --- GPU-aware MPI --------------------------------------------------------
# MPICH_GPU_SUPPORT_ENABLED=1 lets Cray MPICH send device pointers directly.
# It requires the GTL library on the container's link path; if you get
# "GPU_SUPPORT_ENABLED requires GTL" or crashes in device-pointer sends,
# set it to 0 and let the code stage through host memory.
