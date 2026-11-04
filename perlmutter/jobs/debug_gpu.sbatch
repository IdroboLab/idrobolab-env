#!/bin/bash
# Quick correctness check in the debug QOS: 30 minutes max, up to 8 nodes,
# short queue wait. Use this to smoke-test a script before committing it to
# a long regular-QOS run — NOT for production (2 running jobs max).
#
# Charging is the same as regular (QOS factor 1.0), so keep it short.
#
# Usage:  sbatch debug_gpu.sbatch my_script.py [args...]
#         sbatch debug_gpu.sbatch            # runs the built-in smoke test
#
#SBATCH --job-name=eels_debug
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4             # the 4-rank MPI check; the other steps run one task of 32 CPUs
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-node=1
#SBATCH --mem=220G                     # whole node in debug QOS
#SBATCH --time=00:20:00                # debug hard limit is 00:30:00
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

# HDF5 (h5py included) takes a flock on every file it opens, which CFS and
# $HOME do not support from a compute node: the first HDF5 open there fails
# with "OSError: [Errno 524] ... unable to lock file". With the lock off,
# nothing guards one file against two writers.
HDF5_ENV="-e HDF5_USE_FILE_LOCKING=FALSE"

if [ $# -gt 0 ]; then
    SCRIPT=$1; shift
    time srun --ntasks=1 --cpus-per-task=32 podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$WORKDIR" $HDF5_ENV \
        "$IMAGE" python "$SCRIPT" "$@"
    exit 0
fi

# --- built-in smoke test --------------------------------------------------
# `python -P` drops the CWD from sys.path so a stray ./gpaw or ./abtem directory
# cannot shadow the editable install (see README gotchas).
echo "== image identity =="
podman-hpc images --digests | grep -E "REPOSITORY|${IMAGE%%:*}" || true

echo "== GPUs, imports and versions =="
srun --ntasks=1 --cpus-per-task=32 podman-hpc run --rm $GROUP_FLAGS --gpu $MOUNTS "$IMAGE" python -P -c "
import abtem, cupy, gpaw, torch
print('abtem      ', abtem.__version__, abtem.__file__)
print('cupy       ', cupy.__version__, 'CUDA runtime', cupy.cuda.runtime.runtimeGetVersion())
print('torch      ', torch.__version__, 'cuda', torch.cuda.is_available())
print('gpaw       ', gpaw.__version__)
n = cupy.cuda.runtime.getDeviceCount()
print('GPUs       ', n)
for i in range(n):
    print('  device', i, cupy.cuda.runtime.getDeviceProperties(i)['name'].decode())
"

echo "== abTEM plane-wave multislice on the GPU =="
srun --ntasks=1 --cpus-per-task=32 podman-hpc run --rm $GROUP_FLAGS --gpu $MOUNTS "$IMAGE" python -P -c "
import abtem
from ase.build import bulk
abtem.config.set({'device': 'gpu'})
potential = abtem.Potential(bulk('Si', cubic=True), sampling=0.1)
waves = abtem.PlaneWave(energy=200e3).multislice(potential).compute()
print('exit wave on', type(waves.array).__module__, 'norm', float(waves.intensity().array.sum()))
"

echo "== 4-rank MPI world (Cray MPICH injected) =="
srun --ntasks=4 --cpus-per-task=8 podman-hpc run --rm $GROUP_FLAGS --mpi $MOUNTS \
    -e GPAW_MPI_BACKEND=cgpaw "$IMAGE" \
    python -P -c "from gpaw.mpi import world; print(world.rank, '/', world.size)"
