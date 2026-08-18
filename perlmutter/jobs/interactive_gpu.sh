#!/bin/bash
# Interactive shell inside another image's container on Perlmutter GPU nodes.
#
# NERSC's interactive QOS: up to 4 nodes, 4 hours, 2 jobs running at a time,
# charged at the normal rate (QOS factor 1.0) — so a full node held idle for
# 4 hours costs 4 node-hours. Ask for what you need and exit when done.
#
# Usage:
#   ./interactive_gpu.sh                 # 1 node, 4 GPUs, 1 h
#   GPUS=1 TIME=02:00:00 ./interactive_gpu.sh
#   NODES=2 ./interactive_gpu.sh
#   CONSTRAINT="gpu&hbm80g" ./interactive_gpu.sh
#   ./interactive_gpu.sh python -P -c "import gpaw; print(gpaw.__version__)"
set -euo pipefail

ACCOUNT=${ACCOUNT:-<project>_g}        # <- replace; GPU account = _g suffix
CONSTRAINT=${CONSTRAINT:-gpu}
NODES=${NODES:-1}
GPUS=${GPUS:-4}
TIME=${TIME:-01:00:00}
# Image. Accepts a bare name -- IMAGE=otherimage -- or a full reference
# (ghcr.io/user/img:tag, or one pinned by @sha256:...), matching the
# verification launchers and `update-image.sh <name>`. A value containing "/"
# is used verbatim; TAG and IMAGE_OWNER apply only to the short form.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-<username>}/${IMAGE}:${TAG:-latest}" ;;
esac

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Anything after the script name becomes the in-container command; default
# is an interactive bash.
if [ $# -gt 0 ]; then
    CMD=("$@")
    TTY_FLAGS="-i"
else
    CMD=(/bin/bash)
    TTY_FLAGS="-it"
fi

# salloc is the documented interactive entry point on Perlmutter (not
# `srun --pty`). The allocation shell runs on a compute node, so podman-hpc
# runs there directly — no inner srun needed for a single interactive shell.
exec salloc --account="$ACCOUNT" --constraint="$CONSTRAINT" --qos=interactive \
    --nodes="$NODES" --gpus-per-node="$GPUS" --time="$TIME" \
    podman-hpc run --rm $TTY_FLAGS --gpu \
        $MOUNTS --workdir "$PWD" \
        "$IMAGE" "${CMD[@]}"

# CPU-only equivalent (no GPU allocation, charged against the CPU account):
#   salloc -A <project> -C cpu -q interactive -N 1 -t 01:00:00 \
#       podman-hpc run --rm -it -v $SCRATCH:$SCRATCH ghcr.io/<username>/otherimage:latest /bin/bash
