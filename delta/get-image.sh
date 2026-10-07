#!/bin/bash
# Materialize the Delta .sif from the shared image. Preferred path: convert the
# registry image built+pushed by another image's recipe publish.sh (maintained by
# The maintainer, not in this repo).
#
# Run on Delta (or any host with apptainer). On a Delta login node the script
# re-launches itself on a compute node via srun (cpu-interactive by default) and
# streams the build log back: the unpack + multithreaded mksquashfs of a multi-GB
# image is too heavy for a shared login node, where it has aborted with
# `mksquashfs ... malloc(): invalid size (unsorted)`. From inside an salloc shell
# it uses that allocation instead of queueing a new job.
#
#   ACCOUNT=<project>-delta-cpu ./get-image.sh          # see the `accounts` command
#
# Knobs (env): IMAGE, TAG, SIF; PARTITION (cpu-interactive: max 1 h, 2.0x charge;
# use PARTITION=cpu TIME=02:00:00 if a cold-cache download needs longer), TIME,
# CPUS, MEM; MKSQUASHFS_PROCS (defaults to the job's CPU count; needs apptainer
# >= 1.1 for --mksquashfs-args); NO_SRUN=1 builds right here, login node or not.
# APPTAINER_CACHEDIR defaults to $SCRATCH_BASE/$USER/.apptainer (keep off $HOME);
# inside a Slurm job APPTAINER_TMPDIR defaults to a per-job dir on node-local /tmp.
set -euo pipefail
IMAGE=${IMAGE:-ghcr.io/<username>/otherimage}
TAG=${TAG:-latest}
SIF=${SIF:-otherimage_delta.sif}

if [[ $(hostname -s) == dt-login* && ${NO_SRUN:-0} != 1 ]]; then
    SELF=$(readlink -f "$0")
    if [[ -n ${SLURM_JOB_ID:-} ]]; then
        echo ">> in salloc allocation $SLURM_JOB_ID: running the build there"
        exec srun --nodes=1 --ntasks=1 "$SELF"
    fi
    : "${ACCOUNT:?export ACCOUNT=<project>-delta-cpu (see the accounts command)}"
    PARTITION=${PARTITION:-cpu-interactive}
    echo ">> login node: queueing the build on $PARTITION (Ctrl-C cancels the job)"
    # srun propagates the environment (IMAGE/TAG/SIF/...) and the working
    # directory, so a relative SIF lands where it would have locally.
    exec srun --account="$ACCOUNT" --partition="$PARTITION" \
        --nodes=1 --ntasks=1 --cpus-per-task="${CPUS:-16}" --mem="${MEM:-64g}" \
        --time="${TIME:-01:00:00}" --constraint="scratch&projects" \
        --job-name=get-image "$SELF"
fi

if [[ -z ${APPTAINER_CACHEDIR:-} && -n ${SCRATCH_BASE:-} ]]; then
    export APPTAINER_CACHEDIR=$SCRATCH_BASE/$USER/.apptainer
fi
if [[ -n ${SLURM_JOB_ID:-} && -z ${APPTAINER_TMPDIR:-} ]]; then
    export APPTAINER_TMPDIR=/tmp/$USER-apptainer-$SLURM_JOB_ID
    mkdir -p "$APPTAINER_TMPDIR"
    trap 'rm -rf "$APPTAINER_TMPDIR"' EXIT
fi

BUILD_ARGS=()
PROCS=${MKSQUASHFS_PROCS:-${SLURM_CPUS_PER_TASK:-}}
[[ -n $PROCS ]] && BUILD_ARGS+=(--mksquashfs-args "-processors $PROCS")

echo ">> building $SIF on $(hostname -s): cache=${APPTAINER_CACHEDIR:-default}," \
     "tmp=${APPTAINER_TMPDIR:-default}, mksquashfs procs=${PROCS:-all}"

# From the registry (fastest; no local build):
apptainer build "${BUILD_ARGS[@]}" "$SIF" "docker://${IMAGE}:${TAG}"

echo ">> $SIF ready. sha256 for provenance:"; sha256sum "$SIF"
echo ">> run: apptainer exec --nv $SIF python script.py   (see jobs/ for Slurm)"

# Alternatives (uncomment as needed):
# --- local OCI build then convert (no registry): ------------------------------
#   (cd <another image's recipe> && ./prepare_build_context.sh && podman build -t otherimage:latest .)
#   apptainer build "$SIF" docker-daemon://otherimage:latest
