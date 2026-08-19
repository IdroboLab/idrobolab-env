#!/bin/bash
# GPAW / another image MPI job on ONE Perlmutter CPU node (128 ranks).
#
# Unlike the Delta template, the MPI ranks are launched by the HOST `srun`,
# not by an in-container mpiexec: podman-hpc's `--mpi` flag bind-mounts the
# host Cray MPICH over the container's MPICH (both provide libmpi.so.12) and
# wires up PMI, so `srun` spawns one container per rank and they form one
# MPI_COMM_WORLD with native Slingshot transport. This is NERSC's documented
# and supported pattern — there is no need for the Apptainer-style hybrid
# library-injection gymnastics that delta/jobs/gpaw_cpu_multinode.sbatch does.
#
# Node: 2x AMD EPYC 7763 (Milan), 128 physical cores (256 logical), 512 GB.
# Charging: walltime x nodes x 1.0 (Perlmutter charge factor is 1.0).
#
# Usage:  sbatch gpaw_cpu_singlenode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_cpu
#SBATCH --account=<project>                 # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=128          # 1 rank per physical core
#SBATCH --cpus-per-task=2              # 2 x floor(128/tasks_per_node) logical CPUs
#SBATCH --mem=440G                     # 512 GB CPU node (~86% as with 220G/256G)
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
SCRIPT=${1:?usage: sbatch gpaw_cpu_singlenode.sbatch script.py [args]}
shift

# Bind the NERSC filesystems. podman-hpc does not inherit the host mount
# namespace the way Apptainer does, so every path the job touches (input,
# output, PAW setups, code checkouts) must be mounted explicitly.
MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code (see podman-hpc.md,
# "Running your own branches"):
# MOUNTS="$MOUNTS -v $SCRATCH/code/gpaw:/opt/src/gpaw"

# GPAW 26.7.0+ aborts at import ("running inside MPI launcher, but MPI
# parallelism is disabled") when started by an MPI launcher with plain
# `python` unless this is set. The image ships 26.7.1b1, so it is required.
GPAW_ENV="-e GPAW_MPI_BACKEND=cgpaw -e OMP_NUM_THREADS=1"

# Cray MPICH inside a container has no /dev/xpmem, so use CMA for intra-node
# copies; STARTUP_CONNECT helps all-to-all-heavy GPAW startup at high rank
# counts.
MPICH_ENV="-e MPICH_SMP_SINGLE_COPY_MODE=CMA -e MPICH_OFI_STARTUP_CONNECT=1"

echo "IMAGE=$IMAGE  ranks=$SLURM_NTASKS  mounts=$MOUNTS"
time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --mpi \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $GPAW_ENV $MPICH_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# --- Correctness fallback (no Cray MPICH injection) -----------------------
# If `--mpi` misbehaves, drop it: the container's own MPICH 4.3.2 still runs
# correctly over TCP (slower, but fine for modest rank counts on one node).
#   srun podman-hpc run --rm $GROUP_FLAGS $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
#       $GPAW_ENV "$IMAGE" python "$SCRIPT" "$@"
