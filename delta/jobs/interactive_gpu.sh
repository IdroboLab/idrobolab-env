#!/bin/bash
# Interactive shell inside another image's container on one A100
# (gpuA100x4-interactive: max 1 h, charge factor 2.0).
# Adjust ACCOUNT before use; pass a different partition as $1 if wanted
# (e.g. ./interactive_gpu.sh gpuA40x4-interactive).
set -euo pipefail

ACCOUNT=${ACCOUNT:-<project>-delta-gpu}   # <- replace; see `accounts` command
PARTITION=${1:-gpuA100x4-interactive}
SIF=${SIF:-/scratch/${ACCOUNT%-delta-*}/${USER}/containers/otherimage_delta.sif}

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

exec srun --account="$ACCOUNT" --partition="$PARTITION" \
    --nodes=1 --ntasks-per-node=1 --cpus-per-task=16 --mem=32g \
    --gpus-per-node=1 --gpu-bind=closest --time=01:00:00 \
    --constraint="scratch" \
    --pty apptainer exec --nv --bind "$BINDS" "$SIF" /bin/bash
