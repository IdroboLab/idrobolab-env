#!/bin/bash
# GPAW MPI job on ONE Perlmutter CPU node (128 ranks).
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
# Usage:  sbatch -A "$NERSC_PROJECT" gpaw_cpu_singlenode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_cpu
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=128          # 1 rank per physical core
#SBATCH --cpus-per-task=2              # 2 x floor(128/tasks_per_node) logical CPUs
#SBATCH --mem=440G                     # 512 GB CPU node (~86% as with 220G/256G)
#SBATCH --time=02:00:00
# NERSC file-system licenses: see docs/perlmutter/04-jobs.md
#SBATCH --licenses=scratch,cfs
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

# Image. Accepts a bare name -- IMAGE=idrobolab -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-idrobolab}/${IMAGE}:${TAG:-latest}" ;;
esac
SCRIPT=${1:?usage: sbatch gpaw_cpu_singlenode.sbatch script.py [args]}
shift

# Bind the NERSC filesystems. podman-hpc does not inherit the host mount
# namespace the way Apptainer does, so every path the job touches (input,
# output, PAW setups, code checkouts) must be mounted explicitly.
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

# Run a cluster checkout instead of the baked-in code (see docs/perlmutter/reference/podman-hpc.md,
# "Running your own branches"):
# MOUNTS="$MOUNTS -v $SCRATCH/code/gpaw:/opt/src/gpaw"

# GPAW 26.7.0+ aborts at import ("running inside MPI launcher, but MPI
# parallelism is disabled") when started by an MPI launcher with plain
# `python` unless this is set. The image ships 26.7.0, so it is required.
GPAW_ENV="-e GPAW_MPI_BACKEND=cgpaw -e OMP_NUM_THREADS=1"

# Cray MPICH inside a container has no /dev/xpmem, so use CMA for intra-node
# copies; STARTUP_CONNECT helps all-to-all-heavy GPAW startup at high rank
# counts.
MPICH_ENV="-e MPICH_SMP_SINGLE_COPY_MODE=CMA -e MPICH_OFI_STARTUP_CONNECT=1"

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
HDF5_ENV="-e HDF5_USE_FILE_LOCKING=FALSE"

echo "IMAGE=$IMAGE  ranks=$SLURM_NTASKS  mounts=$MOUNTS"
time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --mpi \
        $MOUNTS --workdir "$WORKDIR" \
        $GPAW_ENV $MPICH_ENV \
        $HDF5_ENV "$IMAGE" python "$SCRIPT" "$@"

# --- Correctness fallback (no Cray MPICH injection) -----------------------
# If `--mpi` misbehaves, drop it: the container's own MPICH 4.3.2 still runs
# correctly over TCP (slower, but fine for modest rank counts on one node).
#   srun podman-hpc run --rm $GROUP_FLAGS $MOUNTS --workdir "$WORKDIR" \
#       $GPAW_ENV "$IMAGE" python "$SCRIPT" "$@"
