#!/bin/bash
# ptyrad (ptychographic reconstruction) on one A100 of a SHARED GPU node: the
# default for ptyrad.
#
# NERSC policy: jobs needing only 1 or 2 GPUs SHOULD use the shared QOS.
# A shared job is charged only for the fraction of the node it holds:
#   1 GPU -> 16 physical cores + 64 GB -> 0.25 node-hour per wallclock hour
# Max walltime 48 h, max half a node.
#
# Usage:  sbatch -A "$NERSC_PROJECT" ptyrad_1gpu_shared.sbatch params.yaml [ptyrad run options...]
#
# The params file is a ptyrad .yaml (`ptyrad get-templates` writes starters);
# relative paths in it resolve against the directory you submit from. Options
# after it go to `ptyrad run`, e.g. --seed 1 or --verbosity DEBUG. With no
# seed given, the job draws a random one (Seeds, below).
#
#SBATCH --job-name=ptyrad_1gpu
#SBATCH --account=<project>   # <- replace, or pass sbatch -A "$NERSC_PROJECT"; no _g needed (jobs/README.md)
#SBATCH --constraint=gpu
#SBATCH --qos=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32             # 32 logical = 16 physical cores
#SBATCH --gpus=1
# No --mem, deliberately. Slurm derives a core count from --mem as well as
# from --cpus-per-task and takes the larger; the GPU shared queue then
# rejects anything that is not exactly 32 cores per GPU:
#
#   Logical queue gpu_shared_ss11 requires you to request 32.0 cores per GPU,
#   job requested 38 cores (adjusted for memory) for 1 GPUs
#
# 64 GB is 38 cores at the node's ~1.7 GB per logical core. The slice comes
# with its proportional share (~55 GB per GPU) without asking.
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
PARAMS=${1:?usage: sbatch ptyrad_1gpu_shared.sbatch params.yaml [ptyrad run options]}
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

# One process: give it the threads it paid for (16 physical cores).
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

# HDF5 (through h5py) locks every file it opens, and CFS does not support
# the lock, so ptyrad's first save there fails with
#
#   OSError: [Errno 524] Unable to synchronously create file (unable to lock file, errno = 524, ...)
#
# Locking guards against concurrent writers of one file, which ptyrad does not
# have: under accelerate only the main process saves, and independent runs
# write separate folders.
HDF5_ENV="-e HDF5_USE_FILE_LOCKING=FALSE"

# Seeds. Given neither --seed nor init_params.random_seed, ptyrad runs
# unseeded, and an unseeded run cannot be repeated. The job then draws a seed
# from /dev/urandom and passes it as --seed; ptyrad logs it ("Random seed: <k>
# provided by CLI argument") and saves it with the reconstruction, and --seed
# <k> repeats the run's random choices (initial guesses, batch orders). Seeds
# stay below 2^31: ptyrad seeds numpy with seed + iteration, and numpy rejects
# seeds of 2^32 and above.
draw_seed() { echo $(( $(od -An -N4 -tu4 /dev/urandom) % 2147483648 )); }
seed_given() {   # --seed among the options, or a numeric random_seed in the params
    local a
    for a in "$@"; do case $a in --seed|--seed=*) return 0 ;; esac; done
    # YAML, flow YAML, JSON, TOML and .py params alike; commented-out lines skipped
    grep -Ev '^[[:space:]]*#' "$PARAMS" |
        grep -Eq "random_seed[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[0-9]"
}
SEED_ARGS=()
seed_given "$@" || SEED_ARGS=(--seed "$(draw_seed)")

echo "IMAGE=$IMAGE  gpus=1  mounts=$MOUNTS"
time srun --cpu-bind=cores \
    podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$WORKDIR" \
        $THREAD_ENV $HDF5_ENV \
        "$IMAGE" ptyrad run "$PARAMS" --gpuid 0 "${SEED_ARGS[@]}" "$@"

# For several GPUs on one reconstruction, use ptyrad_2gpu_shared.sbatch or
# ptyrad_4gpu_node.sbatch.
