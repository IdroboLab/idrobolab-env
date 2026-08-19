#!/bin/bash
# Full quad-A100 node on the 80 GB HBM2e variant — the large-GPU-memory
# flagship for another image: complex128 EMCD runs, exact-S2 / large-crop
# asymmetry gates, big abTEM S-matrix budgets that spill 40 GB.
#
# Only 256 of Perlmutter's 1,792 GPU nodes have the 80 GB A100s, so these
# jobs queue longer. The 80 GB parts also have higher HBM bandwidth
# (2039 vs 1555 GB/s). Same charge factor as the 40 GB nodes (1.0).
#
# The `&` in the constraint is a Slurm AND, not shell syntax: it is safe
# unquoted in an #SBATCH line, but MUST be quoted on a command line
# (salloc -C "gpu&hbm80g" ...).
#
# Usage:  sbatch gpu_4gpu_hbm80g.sbatch my_gpu_script.py [args...]
#
#SBATCH --job-name=eels_hbm80g
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu&hbm80g
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none
#SBATCH --exclusive
#SBATCH --mem=220G                     # full 256 GB GPU node
#SBATCH --time=06:00:00
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

# Image. Accepts a bare name -- IMAGE=otherimage -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-<username>}/${IMAGE}:${TAG:-latest}" ;;
esac
SCRIPT=${1:?usage: sbatch gpu_4gpu_hbm80g.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

# Confirm you actually landed on 80 GB parts before a long run — a job that
# silently gets 40 GB will OOM hours in.
echo "IMAGE=$IMAGE  requesting hbm80g"
srun --ntasks=1 podman-hpc run --rm $GROUP_FLAGS --gpu "$IMAGE" \
    nvidia-smi --query-gpu=name,memory.total --format=csv

time srun --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $THREAD_ENV \
        "$IMAGE" python "$SCRIPT" "$@"
