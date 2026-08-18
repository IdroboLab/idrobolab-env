#!/bin/bash
# Multi-GPU verification for abTEM on Delta's gpuA100x4 partition.
# Runs verify_multigpu.py inside another image's container (which ships
# dask-cuda), with the abTEM 'multi-gpu-support' branch injected via PYTHONPATH
# to shadow the container's own abTEM (no venv). NB: the image installs abTEM
# editable from a staged checkout, so its version is NOT a reliable way to tell
# container from branch -- both currently report 1.1.0. Only abtem.__file__ is.
#
# Usage:
#   SIF=/path/otherimage_delta.sif ABTEM_SRC=/path/abTEM \
#     sbatch multigpu_verify.sbatch            # 4 GPUs, default checks
#   (add --timing for a 1-vs-N GPU wall-clock comparison)
#   # optional preflight (no venv):  ABTEM_SRC=/path/abTEM ./setup_env.sh
#
# For 8 GPUs switch the partition/resources below to the gpuA100x8 block, or
# copy this file. Charging: 1 A100-hour = 16 core-hours = 62.5 GB-hours.
#
#SBATCH --job-name=abtem_mgpu
#SBATCH --account=<project>-delta-gpu   # <- replace; see `accounts`
#SBATCH --partition=gpuA100x4
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1             # one python process driving all GPUs
#SBATCH --cpus-per-task=64
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=closest
#SBATCH --exclusive
#SBATCH --mem=220G                     # full 256 GB A100 node
#SBATCH --time=00:10:00
#SBATCH --constraint="scratch&projects"
#SBATCH --output=%x_%j.out
#
# --- 8-GPU variant: comment the four lines above marked (4x) and use ------
# #SBATCH --partition=gpuA100x8
# #SBATCH --cpus-per-task=128
# #SBATCH --gpus-per-node=8
# #SBATCH --mem=0
# --------------------------------------------------------------------------

module reset   # loads defaults, sets $WORK/$SCRATCH; before set -u (Lmod quirk)
set -euo pipefail

# Under `sbatch`, Slurm runs a spool COPY of this script, so BASH_SOURCE points
# at the spool dir (payload absent). Use the submit dir; fall back to the script
# dir for `bash` runs. Submit from the directory holding verify_multigpu.py.
HERE="${SLURM_SUBMIT_DIR:-}"
[ -n "$HERE" ] || HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python payloads are shared with Perlmutter and live in
# shared/verification/multigpu_abtem/; only the launchers are per-cluster, so
# the two clusters cannot drift. Resolved relative to this directory; override
# with PAYLOAD_DIR if you keep the payloads elsewhere.
PAYLOAD_DIR=${PAYLOAD_DIR:-$HERE/../../../shared/verification/multigpu_abtem}
if [ -d "$PAYLOAD_DIR" ]; then
    PAYLOAD_DIR=$(cd "$PAYLOAD_DIR" && pwd)
fi
if [ ! -f "$PAYLOAD_DIR/verify_multigpu.py" ]; then
    echo "ERROR: verify_multigpu.py not found in $PAYLOAD_DIR" >&2
    exit 1
fi

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif}
# abTEM 'multi-gpu-support' checkout. It is injected via PYTHONPATH to shadow the
# container's own abTEM -- no venv: the container is read-only and its Python is
# itself a venv, so a nested venv cannot see the container's dask-cuda/cupy.
ABTEM_SRC=${ABTEM_SRC:-$SCRATCH/code/abTEM}

if [ ! -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    echo "ERROR: abTEM checkout not found at $ABTEM_SRC" >&2
    echo "Set ABTEM_SRC to your 'multi-gpu-support' checkout." >&2
    exit 1
fi

BINDS="$HERE,$PAYLOAD_DIR"
for p in /projects /scratch /work "$ABTEM_SRC"; do
    [ -e "$p" ] && BINDS="${BINDS:+$BINDS,}$p"
done

echo "SIF=$SIF"
echo "abtem_src=$ABTEM_SRC (via PYTHONPATH)"
echo "GPUs requested: ${SLURM_GPUS_ON_NODE:-?}   node=$(hostname)"

# --- injection precheck ----------------------------------------------------
# Cheap (seconds) and it fails loudly instead of producing a green-looking run
# of the WRONG abTEM. This matters more than it looks: the image installs abTEM
# editable from a staged checkout, so the container's own abTEM reports the same
# version as the branch and may itself expose is_gpu_dask_client -- neither the
# version string nor a symbol import can tell them apart. Only the resolved
# PATH can. And verify_multigpu.py records a non-multi-GPU abTEM as WARN, not
# FAIL, then returns `1 if counts["FAIL"] else 0`, so without this gate a failed
# injection exits 0 and looks fine.
#
# The probe PRINTS the path and bash compares it, rather than exiting nonzero
# inside the container: "abtem did not import at all" and "the wrong abtem
# imported" are different problems with different fixes, and collapsing them
# into one status sends the reader to the wrong place.
#
# `python -P` drops the CWD from sys.path so a stray ./abtem directory cannot
# shadow the import; PYTHONPATH is still honoured. `tail -n 1` because only the
# last stdout line is ours.
ABTEM_SRC=${ABTEM_SRC%/}          # a trailing slash would break the match below
if ! ABTEM_PROBE=$(APPTAINERENV_PYTHONPATH="$ABTEM_SRC" \
        apptainer exec --nv --bind "$BINDS" "$SIF" \
        python -P -c 'import abtem; print(abtem.__file__ + "|" + abtem.__version__)' \
        | tail -n 1); then
    echo "ERROR: could not import abtem inside $SIF." >&2
    echo "  This is NOT (yet) the injection failing -- the container did not" >&2
    echo "  run, or abtem did not import at all. Check \$SIF exists and that" >&2
    echo "  the bind list covers it: $BINDS" >&2
    exit 1
fi
ABTEM_FILE=${ABTEM_PROBE%%|*}
ABTEM_VER=${ABTEM_PROBE##*|}
case "$ABTEM_FILE" in
    "$ABTEM_SRC"/*)
        echo "abtem in use: $ABTEM_VER  <- $ABTEM_FILE" ;;
    *)
        echo "ERROR: the branch abTEM is not the one being imported." >&2
        echo "  imported: $ABTEM_FILE ($ABTEM_VER)" >&2
        echo "  expected: somewhere under $ABTEM_SRC" >&2
        echo "  The container's own abTEM won (editable, /opt/src/abTEM). If it" >&2
        echo "  was built from a checkout without the multi-GPU work, every check" >&2
        echo "  below would be testing nothing; if it was built from one WITH it," >&2
        echo "  the run would pass while telling you nothing about your branch." >&2
        echo "  The version string would not have revealed either case." >&2
        echo "  Check APPTAINERENV_PYTHONPATH and that \$ABTEM_SRC is in --bind." >&2
        exit 1 ;;
esac

# --nv exposes the GPUs; PYTHONPATH makes the container Python import the branch
# abTEM while dask-cuda/cupy/dask come from the container.
time APPTAINERENV_PYTHONPATH="$ABTEM_SRC" apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$PAYLOAD_DIR/verify_multigpu.py" "$@"
