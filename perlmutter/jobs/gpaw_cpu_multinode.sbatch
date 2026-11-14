#!/bin/bash
# GPAW MPI job across MULTIPLE Perlmutter CPU nodes.
#
# Identical launch mechanism to the single-node script (srun + podman-hpc
# --mpi); only the node count and a couple of Slingshot knobs change. On
# Perlmutter the multi-node case is NOT a separate, riskier code path the way
# it is on Delta — the Cray MPICH swap-in is the same either way.
#
# Node: 2x AMD EPYC 7763 (Milan), 128 physical cores (256 logical), 512 GB.
# Charging: walltime x nodes x 1.0.  4 nodes x 2 h = 8 CPU node-hours.
#
# Usage:  sbatch -A "$NERSC_PROJECT" gpaw_cpu_multinode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_mpi
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=128          # 512 ranks total
#SBATCH --cpus-per-task=2
#SBATCH --mem=440G                     # 512 GB CPU node (~86% as with 220G/256G)
#SBATCH --time=04:00:00
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
SCRIPT=${1:?usage: sbatch gpaw_cpu_multinode.sbatch script.py [args]}
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
GPAW_ENV="-e GPAW_MPI_BACKEND=cgpaw -e OMP_NUM_THREADS=1"

MPICH_ENV="-e MPICH_SMP_SINGLE_COPY_MODE=CMA -e MPICH_OFI_STARTUP_CONNECT=1"

# Multi-node podman-hpc MPI sometimes fails PMPI init with a misleading
# "No space left on device" — NERSC's fix is to disable the VNI network
# feature. Harmless when not needed; drop it if you prefer to test without.
NETOPT="--network=no_vni"

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
HDF5_ENV="-e HDF5_USE_FILE_LOCKING=FALSE"

echo "IMAGE=$IMAGE  nodes=$SLURM_JOB_NUM_NODES  ranks=$SLURM_NTASKS"
time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --mpi $NETOPT \
        $MOUNTS --workdir "$WORKDIR" \
        $GPAW_ENV $MPICH_ENV \
        $HDF5_ENV "$IMAGE" python "$SCRIPT" "$@"

# --- Scaling notes --------------------------------------------------------
# * GPAW rarely scales past a few hundred ranks on a single SCF; prefer
#   band/domain/kpt parallelisation tuning over simply adding nodes, and
#   check the "Parallelization" block GPAW prints in the .txt output.
# * If startup dominates at >512 ranks, try dropping MPICH_OFI_STARTUP_CONNECT
#   (it trades startup cost for steady-state latency, and the win flips).
# * Slingshot multithreaded hangs (mpich #7184): add
#   -e FI_CXI_RX_MATCH_MODE=hybrid
