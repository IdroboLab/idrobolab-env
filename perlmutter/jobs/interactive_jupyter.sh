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
# Defaults to ONE GPU on `shared_interactive`: a fraction of a node, charged
# for the fraction held (a 1-GPU slice is 0.25 node-hours per wallclock hour,
# 4x cheaper than a whole node), and served from the interactive reservation so
# it starts promptly. An idle notebook is charged exactly like a busy one, so
# keep TIME short and exit when done -- restarting is cheap.
#
# NOT the plain `shared` QOS, which is what you want for sbatch work but is a
# BATCH queue: an interactive session submitted there sits behind regular jobs
# and can take far too long to start.
#
# QOS=interactive takes a whole node (factor 1.0, <=4 h, 2 jobs at a time) if
# the slice will not do, or if shared_interactive is unavailable.
set -euo pipefail

# Preserve supplementary group membership inside the container -- see the long
# note in interactive_gpu.sh. Set PODMAN_GROUP_FLAGS= to disable.
GROUP_FLAGS=${PODMAN_GROUP_FLAGS---group-add keep-groups}

ACCOUNT=${ACCOUNT:-<project>_g}            # override with -A; see jobs/README.md on _g
CONSTRAINT=${CONSTRAINT:-gpu}
QOS=${QOS:-shared_interactive}         # or interactive, for a whole node
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

# On the slice QOSes (`shared`, `shared_interactive`) you are charged for the
# slice you hold, so the slice has to be spelled out: NERSC's per-GPU share of
# a GPU node is 32 logical (16 physical) cores. On interactive/regular the
# allocation is whole nodes and only the GPU count matters.
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
    shared|shared_interactive)
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

# Publish the port. Required, and confirmed the hard way: without it the server
# binds 0.0.0.0:$PORT inside a PRIVATE network namespace, where nothing outside
# the container can reach it -- not the login node, not the compute node it runs
# on. Adding -p was the single change that made this work.
#
# Do not be misled by /proc/net/dev inside the container showing hsn0: podman-hpc
# gives the container a view of the host /proc, so it describes the node rather
# than the namespace. See docs/perlmutter/reference/podman-hpc.md, "Networking". PUBLISH=0 drops it.
PUBLISH_FLAGS=""
[ "${PUBLISH:-1}" = "0" ] || PUBLISH_FLAGS="-p $PORT:$PORT"

# --port-retries=0 matters: by default Jupyter silently walks to the next free
# port if $PORT is taken, which would leave the ssh line printed below pointing
# at nothing. Better to fail loudly and pick another PORT.
#
# --allow-root is not optional: `jupyter lab` REFUSES to start as uid 0 without
# it (a [C] line, then it exits). The container does run as root, and under
# rootless podman that root IS your own host uid -- see docs/perlmutter/reference/podman-hpc.md,
# "The container runs as root, and that is correct here".
JUPYTER_ARGS="--no-browser --ip=0.0.0.0 --port=$PORT --port-retries=0 --allow-root"

# The image's HOME is /root, which lives in the container's ephemeral overlay
# and vanishes with --rm. Point it at the real home (mounted above) so tokens,
# kernels, jupyter settings and installed extensions survive the session.
HOME_ENV="-e HOME=$HOME"

# Everything the inner shell needs, passed through the environment rather than
# through another layer of quoting (salloc exports the caller's environment).
export MOUNTS WORKDIR IMAGE PORT GROUP_FLAGS RUN_GPU_FLAGS SHM_FLAGS THREAD_ENV HOME_ENV PUBLISH_FLAGS JUPYTER_ARGS

# Say what is being asked for BEFORE salloc blocks: if it does queue, this is
# the line that tells you which QOS to blame.
echo "requesting: qos=$QOS ${GPUS} GPU(s) ${CPUS} logical cores, $TIME" >&2
echo "  (Ctrl-C and retry with QOS=interactive GPUS=4 if this does not start)" >&2

# salloc with an explicit command runs THAT COMMAND ON THE LOGIN NODE -- only
# srun steps land on the allocated node. Getting this wrong is silent and
# expensive: the container starts, Jupyter serves, and everything runs on a
# shared login node with no GPU while the allocation sits idle. The giveaway
# is a banner naming loginNN when salloc said "Nodes nidNNNNNN are ready".
#
# So: the inner shell (login node) reads the node name from $SLURM_NODELIST for
# the tunnel, and srun places the container on it.
exec salloc --account="$ACCOUNT" --constraint="$CONSTRAINT" --qos="$QOS" \
    --nodes="$NODES" $SALLOC_RES --time="$TIME" --job-name=jupyter \
    bash -c '
        node=$(scontrol show hostnames "$SLURM_NODELIST" | head -1)
        cat >&2 <<EOF

  ---------------------------------------------------------------------------
  JupyterLab is starting on $node:$PORT

  On your LAPTOP:

      ssh -N -L $PORT:$node:$PORT '"${USER:-\$USER}"'@perlmutter.nersc.gov

  Then open the URL the server prints below, with its host replaced:

      http://localhost:$PORT/lab?token=<token from the output below>

  (the host it advertises is the container ID, not $node -- ignore it)

  Keep THIS terminal open -- Ctrl-C here ends the server AND the allocation.
  Run the ssh line in a second terminal, while the server is still up.
  ---------------------------------------------------------------------------

EOF
        # Prove the exact path the tunnel will use: this login node -> the
        # port on the compute node. `ssh -L` relays through a login node, so a
        # failure here cannot be fixed at the laptop end. Backgrounded, so it
        # reports while Jupyter starts; exits as soon as the port answers.
        #
        # It announces itself first: a probe that says nothing is
        # indistinguishable from a probe that never ran, and the answer line
        # is easy to miss in the middle of the server log.
        #
        # curl for the test where available -- bash net redirection
        # (/dev/tcp) is a compile-time option and not guaranteed present.
        # (No apostrophes in this block -- it lives inside a quoted bash -c.)
        ( echo "  [check] probing $node:$PORT from $(hostname), up to 90 s ..." >&2
          if command -v curl >/dev/null 2>&1; then
              _probe() { curl -s -o /dev/null --max-time 2 "http://$1:$2/"; }
          elif (exec 3<>/dev/tcp/127.0.0.1/22) 2>/dev/null || [ $? -ne 127 ]; then
              _probe() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }
          else
              echo "  [check] no curl and no bash /dev/tcp -- cannot probe; try the tunnel and see" >&2
              exit 0
          fi
          for _ in $(seq 45); do
              sleep 2
              if _probe "$node" "$PORT"; then
                  echo "  [check] $node:$PORT ANSWERS -- run the ssh -L line now" >&2
                  exit 0
              fi
          done
          echo "  [check] NO answer from $node:$PORT after 90 s -- the tunnel will refuse too" >&2
          # Distinguish the two explanations without a second session: ask the
          # compute node itself. A listener visible there but not from here is
          # a network block between login and compute; nothing listening there
          # means the port lives inside a private namespace and never reached
          # the node at all.
          echo "  [check] asking $node what is listening on $PORT ..." >&2
          timeout 60 srun --overlap -N1 -n1 bash -c \
              "ss -ltn 2>/dev/null | grep :$PORT || echo none" >&2
          ) &
        exec srun --unbuffered podman-hpc run --rm -i $GROUP_FLAGS $RUN_GPU_FLAGS $SHM_FLAGS \
            $PUBLISH_FLAGS $MOUNTS --workdir "$WORKDIR" $THREAD_ENV $HOME_ENV \
            "$IMAGE" jupyter lab $JUPYTER_ARGS "$@"
    ' bash "$@"

# Notes
# -----
# * Ctrl-C in the launching terminal goes to srun, not to Jupyter: srun asks
#   for a second Ctrl-C within 1 s, then cancels the step and the allocation.
#   That is the intended way to finish -- it frees the slice immediately. It
#   also means the server is gone the moment you press it, so run the ssh -L
#   line from a SECOND terminal while this one is still streaming logs.
# * The tunnel binds $PORT on your LAPTOP and forwards to $PORT on the compute
#   node; the login node only relays. Nothing is bound on the login node, so
#   there is no collision with other users there.
# * The port IS open on the compute node to anyone who can route to it. Keep
#   the token -- do not add --ServerApp.token='' to save typing.
# * A dropped tunnel does not kill the server: re-run the ssh line only.
# * Check what you actually got: `scontrol show job $SLURM_JOB_ID | grep -i qos`
#   inside the allocation, or `squeue --me -o "%i %q %P %T %r"` from another
#   shell -- the last column gives the pending reason when it does not start.
# * QOS=shared is the BATCH slice queue. It works, but an interactive session
#   there waits behind regular jobs; that is what shared_interactive exists to
#   avoid. Use `shared` for sbatch, not for this.
