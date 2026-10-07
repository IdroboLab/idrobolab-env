#!/bin/bash
# Interactive shell inside the idrobolab container on 1 or 2 GPUs of a SHARED
# Perlmutter GPU node.
#
# NERSC's shared_interactive QOS: a fraction of a node (at most half, 2 GPUs),
# 4 hours at most, charged only for the fraction held:
#   1 GPU -> 16 physical cores + 64 GB -> 0.25 node-hour per wallclock hour
#   2 GPU -> 32 physical cores + 128 GB -> 0.5  node-hour per wallclock hour
# Use interactive_gpu.sh when all 4 GPUs (a whole node) are needed. An idle
# session is charged like a busy one: exit when done.
#
# Usage:
#   ./interactive_gpu_shared.sh                 # 1 GPU, 1 h
#   GPUS=2 TIME=02:00:00 ./interactive_gpu_shared.sh
#   ./interactive_gpu_shared.sh python -P -c "import abtem; print(abtem.__version__)"
#
# GPUS is 1 or 2; anything else is refused. TIME is passed to salloc as it is
# (HH:MM:SS; shared_interactive allows at most 4 h and Slurm reports its own limit).
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

ACCOUNT=${ACCOUNT:-<project>_g}            # override with sbatch -A; see jobs/README.md on _g
CONSTRAINT=${CONSTRAINT:-gpu}
GPUS=${GPUS:-1}
TIME=${TIME:-01:00:00}

# The shared queue wants exactly 32 logical cores per GPU, and the two GPU
# counts need different spellings: --gpus-per-task=2 with -c 64 is rejected
# ("requires you to request 32.0 cores per GPU, job requested 64 cores ... for
# 1 GPUs"), --gpus=2 is accepted. No --mem: see jobs/README.md.
case "$GPUS" in
    1) GPU_FLAGS="--gpus-per-task=1" ;;
    2) GPU_FLAGS="--gpus=2" ;;
    *) echo "GPUS must be 1 or 2 (got '$GPUS'); use interactive_gpu.sh for a whole node" >&2; exit 2 ;;
esac
CPUS=$((32 * GPUS))

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
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}" "$PWD"; do
    add_mount "$p"
done
WORKDIR=$(pwd -P)

# Anything after the script name becomes the in-container command; default
# is an interactive bash.
# --pty on srun for the interactive shell, so the terminal behaves; a one-shot
# command wants plain srun and its unbuffered output.
if [ $# -gt 0 ]; then
    CMD=("$@")
    TTY_FLAGS="-i"
    SRUN_FLAGS="--unbuffered"
else
    CMD=(/bin/bash)
    TTY_FLAGS="-it"
    SRUN_FLAGS="--pty"
fi

# salloc with an explicit command runs THAT COMMAND ON THE LOGIN NODE -- only
# srun steps land on the allocated node. Without the inner srun the container
# runs on a shared login node, with no GPU, while the allocation sits idle.
# (`salloc` with NO command is the case that drops you onto the compute node;
# passing a command overrides that.)
exec salloc --account="$ACCOUNT" --constraint="$CONSTRAINT" --qos=shared_interactive \
    --nodes=1 --ntasks=1 --cpus-per-task="$CPUS" $GPU_FLAGS --time="$TIME" \
    srun $SRUN_FLAGS podman-hpc run --rm $GROUP_FLAGS $TTY_FLAGS --gpu \
        $MOUNTS --workdir "$WORKDIR" -e HOME="$HOME" -e SCRATCH="${SCRATCH:-}" \
        "$IMAGE" "${CMD[@]}"

