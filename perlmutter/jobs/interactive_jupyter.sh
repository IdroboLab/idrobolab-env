#!/bin/bash
# JupyterLab inside the container on a Perlmutter compute node, reachable from
# the browser on your laptop through an ssh tunnel.
#
# It allocates the node, starts the server, and prints the exact `ssh -L` line
# to paste on your laptop -- with the real node name filled in, which is the
# one thing you cannot know before the allocation is granted.
#
# Usage:
#   ./interactive_jupyter.sh                    # 1 A100 on a shared node, 2 h, port 8899
#   PORT=9100 ./interactive_jupyter.sh
#   GPUS=2 TIME=04:00:00 ./interactive_jupyter.sh
#   QOS=interactive GPUS=4 ./interactive_jupyter.sh                # whole GPU node
#   GPUS=0 CONSTRAINT=cpu ACCOUNT=<project> ./interactive_jupyter.sh   # CPU session
#   ./interactive_jupyter.sh --ServerApp.root_dir=$SCRATCH         # extra jupyter args
#
# Then, on your laptop, paste the printed line and open the printed URL. The
# token is in the server's own output; the HOST it advertises is the container
# ID (podman gives the container its own UTS namespace), so ignore that part
# and use localhost.
#
# Defaults to ONE GPU on the `shared` QOS, which is what NERSC policy asks for
# at 1-2 GPUs and is 4x cheaper than holding a whole node: a 1-GPU slice is
# 0.25 node-hours per wallclock hour. An idle notebook is charged exactly like
# a busy one, so keep TIME short and exit when done -- restarting is cheap.
#
# QOS=interactive gets you a whole node instead (factor 1.0, <=4 h, 2 jobs at a
# time) and generally starts sooner, since `shared` queues behind regular work.
set -euo pipefail

# Preserve supplementary group membership inside the container -- see the long
# note in interactive_gpu.sh. Set PODMAN_GROUP_FLAGS= to disable.
GROUP_FLAGS=${PODMAN_GROUP_FLAGS---group-add keep-groups}

ACCOUNT=${ACCOUNT:-<project>_g}            # override with -A; see jobs/README.md on _g
CONSTRAINT=${CONSTRAINT:-gpu}
QOS=${QOS:-shared}                     # or interactive, for a whole node
NODES=${NODES:-1}
GPUS=${GPUS:-1}                        # 0 for a CPU-only session
TIME=${TIME:-02:00:00}
PORT=${PORT:-8899}
# /dev/shm inside the container defaults to 64 MB, which is not enough for
# dask workers. Off unless asked for: SHM_SIZE=32g ./interactive_jupyter.sh
SHM_FLAGS=${SHM_SIZE:+--shm-size=$SHM_SIZE}

# Image. Accepts a bare name -- IMAGE=otherimage -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-<username>}/${IMAGE}:${TAG:-latest}" ;;
esac

# On `shared` you are charged for the slice you hold, so the slice has to be
# spelled out: NERSC's per-GPU share of a GPU node is 32 logical (16 physical)
# cores. On interactive/regular the allocation is whole nodes and only the GPU
# count matters.
#
# Do NOT also ask for the matching memory. Slurm derives a core count from
# --mem as well as from --cpus-per-task, takes the larger of the two, and the
# GPU shared queue then rejects anything that is not exactly 32 cores per GPU:
#
#   salloc: error: Logical queue gpu_shared_ss11 requires you to request 32.0
#   cores per GPU, job requested 38 cores (adjusted for memory) for 1 GPUs
#
# 64 GB is 38 cores at the node's ~1.7 GB per logical core, so spelling out
# the memory share is exactly what breaks the request. Left unset, the slice
# arrives with its proportional share anyway. MEM= is still honoured if you
# have a reason to pin it -- keep it under 32 cores' worth (~55 GB per GPU).
CPUS=${CPUS:-$(( GPUS > 0 ? GPUS * 32 : 32 ))}
MEM=${MEM:-}

# GPUs are opt-out: GPUS=0 gives a CPU session (pair it with CONSTRAINT=cpu and
# the non-_g account, or Slurm rejects the combination).
RUN_GPU_FLAGS=""
if [ "$GPUS" -gt 0 ] 2>/dev/null; then
    RUN_GPU_FLAGS="--gpu"
fi
case "$QOS" in
    shared)
        SALLOC_RES="--ntasks=1 --cpus-per-task=$CPUS${MEM:+ --mem=$MEM}"
        if [ -n "$RUN_GPU_FLAGS" ]; then
            SALLOC_RES="$SALLOC_RES --gpus=$GPUS"
        fi ;;
    *)
        SALLOC_RES=""
        if [ -n "$RUN_GPU_FLAGS" ]; then
            SALLOC_RES="--gpus-per-node=$GPUS"
        fi ;;
esac

# Give the notebook the physical cores it is paying for -- the image defaults
# OMP_NUM_THREADS=1, which would leave a shared-QOS slice mostly idle.
THREADS=${THREADS:-$(( CPUS / 2 ))}
THREAD_ENV="-e OMP_NUM_THREADS=$THREADS -e OPENBLAS_NUM_THREADS=$THREADS"

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
    local p=${1:-} m twin
    [ -n "$p" ] && [ -d "$p" ] || return 0
    p=$(cd "$p" && pwd -P)
    # Skip a path already mounted or contained in one: an identical destination
    # is a hard podman error ("duplicate mount destination"), a nested one just
    # shadows part of its parent.
    for m in $_mounted; do
        case "$p" in "$m" | "$m"/*) return 0 ;; esac
    done
    _mounted="$_mounted $p"
    MOUNTS="$MOUNTS -v $p:$p"
    # Mirror the cluster: the same directory answers to a projectdirs name
    # there, so give the container that name too, mounted FROM that name so
    # `podman inspect` and any error message read like the paths people type.
    # Fall back to the canonical source if the symlink is not there.
    case "$p" in
        /global/cfs/cdirs/*)
            twin="/global/cfs/projectdirs/${p#/global/cfs/cdirs/}"
            if [ -d "$twin" ]; then
                MOUNTS="$MOUNTS -v $twin:$twin"
            else
                MOUNTS="$MOUNTS -v $p:$twin"
            fi ;;
    esac
}
# Broad filesystems first, so the working directory collapses into whichever
# one holds it instead of adding a redundant nested mount.
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}" "$PWD"; do
    add_mount "$p"
done
WORKDIR=$(pwd -P)

# No -p/--publish anywhere below, and that is not an oversight: podman-hpc runs
# the container on the HOST network namespace (verified on a compute node --
# hsn0 with live counters is visible inside), so --ip=0.0.0.0 binds $PORT
# directly on the node. Adding -p here would be discarded with a warning. See
# ../podman-hpc.md, "Networking".
#
# --port-retries=0 matters: by default Jupyter silently walks to the next free
# port if $PORT is taken, which would leave the ssh line printed below pointing
# at nothing. Better to fail loudly and pick another PORT.
JUPYTER_ARGS="--no-browser --ip=0.0.0.0 --port=$PORT --port-retries=0"

# Everything the inner shell needs, passed through the environment rather than
# through another layer of quoting (salloc exports the caller's environment).
export MOUNTS WORKDIR IMAGE PORT GROUP_FLAGS RUN_GPU_FLAGS SHM_FLAGS THREAD_ENV JUPYTER_ARGS

# salloc is the documented interactive entry point on Perlmutter (not
# `srun --pty`), and its shell runs on the compute node -- so `hostname` below
# is the node you need in the tunnel, and podman-hpc runs there directly.
exec salloc --account="$ACCOUNT" --constraint="$CONSTRAINT" --qos="$QOS" \
    --nodes="$NODES" $SALLOC_RES --time="$TIME" --job-name=jupyter \
    bash -c '
        node=$(hostname)
        cat >&2 <<EOF

  ---------------------------------------------------------------------------
  JupyterLab is starting on $node:$PORT

  On your LAPTOP:

      ssh -N -L $PORT:$node:$PORT '"${USER:-\$USER}"'@perlmutter.nersc.gov

  Then open the URL the server prints below, with its host replaced:

      http://localhost:$PORT/lab?token=<token from the output below>

  (the host it advertises is the container ID, not $node -- ignore it)
  ---------------------------------------------------------------------------

EOF
        exec podman-hpc run --rm -i $GROUP_FLAGS $RUN_GPU_FLAGS $SHM_FLAGS \
            $MOUNTS --workdir "$WORKDIR" $THREAD_ENV \
            "$IMAGE" jupyter lab $JUPYTER_ARGS "$@"
    ' bash "$@"

# Notes
# -----
# * The tunnel binds $PORT on your LAPTOP and forwards to $PORT on the compute
#   node; the login node only relays. Nothing is bound on the login node, so
#   there is no collision with other users there.
# * The port IS open on the compute node to anyone who can route to it. Keep
#   the token -- do not add --ServerApp.token='' to save typing.
# * Ctrl-C stops the server; the allocation ends with it because salloc exits.
# * A dropped tunnel does not kill the server: re-run the ssh line only.
# * `shared` is not an interactive QOS: the allocation queues behind regular
#   work, so a busy machine can leave you waiting. QOS=interactive GPUS=4 is
#   the fast-start alternative at 4x the charge.
