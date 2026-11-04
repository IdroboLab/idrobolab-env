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
# NERSC file-system licenses: see docs/perlmutter/04-jobs.md
#SBATCH --licenses=scratch,cfs
#SBATCH --output=%x_%j.out

set -euo pipefail

# NOTE: a script that drives more than one GPU needs an
#   if __name__ == "__main__":
# guard around everything that does work. dask-cuda starts its workers with
# multiprocessing spawn (fork is unsafe with a live CUDA context), and spawn
# re-imports the main module in each child -- module-level work then re-runs
# per worker and tries to start a nested cluster. See jobs/README.md.

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

# Image. Accepts a bare name -- IMAGE=idrobolab -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-idrobolab}/${IMAGE}:${TAG:-latest}" ;;
esac
SCRIPT=${1:?usage: sbatch gpu_multinode_mpi.sbatch script.py [args]}
shift

# Bind-mounts + the in-container working directory. podman-hpc mounts nothing
# by default, so every path the job reads or writes needs an explicit -v; each
# is mounted at its own name so an absolute path means the same thing on both
# sides.
#
# NERSC spells the community filesystem two ways -- /global/cfs/cdirs/<project>
# and /global/cfs/projectdirs/<project>, a symlink to it -- and $CFS is the
# first. Working from the second used to fail before the payload ever started:
#
#   Error: workdir "/global/cfs/projectdirs/<project>/..." does not exist on container <id>
#
# So resolve to the canonical path (`pwd -P` follows the symlink) and mount
# every CFS tree under BOTH names: either spelling then works, as the working
# directory and in paths handed to the payload. See jobs/README.md.
MOUNTS=""
_mounted=""
add_mount() {
    local p=${1:-} m twin given
    [ -n "$p" ] && [ -d "$p" ] || return 0
    given=$p
    p=$(cd "$p" && pwd -P)
    # Skip a path already mounted or contained in one: an identical destination
    # is a hard podman error ("duplicate mount destination"), a nested one just
    # shadows part of its parent.
    for m in $_mounted; do
        case "$p" in "$m" | "$m"/*) return 0 ;; esac
    done
    _mounted="$_mounted $p"
    MOUNTS="$MOUNTS -v $p:$p"
    # Also mount it under the name we were GIVEN, when that is a symlink to the
    # canonical one. $HOME is the case that matters: NERSC sets it to
    # /global/homes/<i>/<user>, a symlink to /global/u1/<i>/<user>. Mounting only
    # the resolved name leaves $HOME itself non-existent inside the container --
    # which reads as "not a writable location", and anything that resolves $HOME
    # (Jupyter runtime dirs, ~/.config) lands in the ephemeral overlay instead.
    [ "$given" = "$p" ] || MOUNTS="$MOUNTS -v $p:$given"
    # Mirror the cluster: the same directory answers to a projectdirs name
    # there, so give the container that name too, mounted FROM that name so
    # `podman inspect` and any error message read like the paths people type.
    # Fall back to the canonical source if the symlink is not there.
    # $CFS is often the bare /global/cfs/cdirs, so match that too -- the
    # /*-only pattern silently produced no twin at all for it.
    case "$p" in
        /global/cfs/cdirs)   twin="/global/cfs/projectdirs" ;;
        /global/cfs/cdirs/*) twin="/global/cfs/projectdirs/${p#/global/cfs/cdirs/}" ;;
        *)                   twin="" ;;
    esac
    if [ -n "$twin" ] && [ "$twin" != "$given" ]; then
        if [ -d "$twin" ]; then
            MOUNTS="$MOUNTS -v $twin:$twin"
        else
            MOUNTS="$MOUNTS -v $p:$twin"
        fi
    fi
}
# Broad filesystems first, so the working directory collapses into whichever
# one holds it instead of adding a redundant nested mount.
#
# Plain $PWD, not ${SLURM_SUBMIT_DIR:-$PWD}: SLURM only sets SLURM_SUBMIT_DIR
# once, at salloc time, to wherever salloc was invoked from -- it does not
# track cd afterward. Trusting it here silently resolved every later
# invocation in the same interactive session back to that original directory
# (usually $HOME) regardless of where the script was actually run from.
# $PWD is always correct in both the sbatch case (SLURM starts the batch
# script's cwd at the submission directory, so $PWD already equals
# SLURM_SUBMIT_DIR there) and the salloc+bash case this silently broke.
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}" "$PWD"; do
    add_mount "$p"
done
WORKDIR=$(pwd -P)

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

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
HDF5_ENV="-e HDF5_USE_FILE_LOCKING=FALSE"

echo "IMAGE=$IMAGE  nodes=$SLURM_JOB_NUM_NODES  ranks=$SLURM_NTASKS"
srun --cpu-bind=cores podman-hpc run --rm $GROUP_FLAGS --gpu $MOUNTS "$IMAGE" \
    bash -c 'echo "rank $SLURM_PROCID localid $SLURM_LOCALID sees $(nvidia-smi -L | wc -l) GPUs"' \
    || echo "(GPU visibility probe failed — check --gpu / binding)"

time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --mpi --gpu --nccl-cu12 --network=no_vni \
        $MOUNTS --workdir "$WORKDIR" \
        $GPAW_ENV $MPICH_ENV $RANK_ENV \
        $HDF5_ENV "$IMAGE" python "$SCRIPT" "$@"

# --- GPU-aware MPI --------------------------------------------------------
# MPICH_GPU_SUPPORT_ENABLED=1 lets Cray MPICH send device pointers directly.
# It requires the GTL library on the container's link path; if you get
# "GPU_SUPPORT_ENABLED requires GTL" or crashes in device-pointer sends,
# set it to 0 and let the code stage through host memory.
