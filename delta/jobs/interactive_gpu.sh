#!/bin/bash
# Interactive shell inside the idrobolab container on one A100
# (gpuA100x4-interactive: max 1 h, charge factor 2.0).
# ACCOUNT defaults to your -delta-gpu account (from DELTA_PROJECT, see delta/env.sh).
# Pass a different partition as $1 if wanted (e.g. ./interactive_gpu.sh gpuA40x4-interactive).
set -euo pipefail

# shellcheck source=../../core/shell/accounts.sh
. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../../core/shell/accounts.sh"
# An exported ACCOUNT wins; otherwise the -delta-gpu account env.sh's variables give.
ACCOUNT=${ACCOUNT:-$(hpcenv_account gpu || true)}
: "${ACCOUNT:?export ACCOUNT=<project>-delta-gpu (see the accounts command), or DELTA_PROJECT=<project> in ~/.bashrc above the idrobolab-env block}"
PARTITION=${1:-gpuA100x4-interactive}
SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif}

BINDS=""
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="${BINDS:+$BINDS,}$p"; done

# Set the GPAW MPI backend up front so an in-shell `mpiexec -bootstrap fork -n N
# python ...` just works (GPAW 26.7.0+ aborts at import under a launcher with
# the default 'serial' backend). Harmless for serial use: with one process the
# cgpaw backend is simply a size-1 world, which is what `gpaw python` does too.
export APPTAINERENV_GPAW_MPI_BACKEND=cgpaw

exec srun --account="$ACCOUNT" --partition="$PARTITION" \
    --nodes=1 --ntasks-per-node=1 --cpus-per-task=16 --mem=32g \
    --gpus-per-node=1 --gpu-bind=closest --time=01:00:00 \
    --constraint="scratch&projects" \
    --pty apptainer exec --nv --bind "$BINDS" "$SIF" /bin/bash
