#!/bin/bash
# Multi-GPU verification for abTEM on Delta's gpuA100x4 partition.
# Runs verify_multigpu.py inside the idrobolab container (which ships
# dask-cuda), with the abTEM 'multi-gpu-support' branch injected via PYTHONPATH
# to shadow the container's own abTEM (no venv). NB: the image installs abTEM
# editable from a staged checkout, so its version is NOT a reliable way to tell
# container from branch -- both currently report 1.1.0. Only abtem.__file__ is.
#
# Usage:
#   SIF=/path/idrobolab.sif ABTEM_SRC=/path/abTEM \
#     sbatch multigpu_verify.sbatch            # 4 GPUs, default checks
#   (add --timing for a 1-vs-N GPU wall-clock comparison)
#   # optional preflight (no venv):  ABTEM_SRC=/path/abTEM ./setup_env.sh#
#   Image selection: SIF is the .sif path; IMAGE=<name> resolves to
#   $PROJECTS_BASE/software/containers/<name>.sif (default idrobolab),
#   matching the short-name form used by the Perlmutter launchers.
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

module reset   # loads defaults, $SCRATCH_BASE comes from delta/env.sh (Delta sets $SCRATCH only inside jobs); before set -u (Lmod quirk)
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

# Image selection. SIF is the .sif path and always wins when set. IMAGE gives
# the short-name form used elsewhere in the repo -- `IMAGE=idrobolab` resolves
# to <containers>/idrobolab.sif -- and an absolute path in IMAGE is taken
# as-is, so either variable can carry a path.
IMAGE=${IMAGE:-idrobolab}
case "$IMAGE" in
    /*) SIF=${SIF:-$IMAGE} ;;
    *)  SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/${IMAGE}.sif} ;;
esac
if [ ! -f "$SIF" ]; then
    echo "ERROR: container image not found: $SIF" >&2
    echo "  Set SIF=/path/to/image.sif, or IMAGE=<name> for" >&2
    echo "  \$PROJECTS_BASE/software/containers/<name>.sif" >&2
    exit 1
fi
# abTEM 'multi-gpu-support' checkout. It is injected via PYTHONPATH to shadow the
# container's own abTEM -- no venv: the container is read-only and its Python is
# itself a venv, so a nested venv cannot see the container's dask-cuda/cupy.
if [ -n "${ABTEM_SRC+x}" ]; then ABTEM_SRC_GIVEN=1; else ABTEM_SRC_GIVEN=0; fi
ABTEM_SRC=${ABTEM_SRC-$HERE/code/abTEM}

# Which abTEM gets tested. ABTEM_SRC names a checkout to inject over the
# container's own copy. Leaving it out is legitimate: the image installs abTEM
# editable from a staged checkout that may already carry the multi-GPU work, and
# testing that copy is a real thing to want.
#
#   ABTEM_SRC unset    the default path if it exists, else the container's abTEM
#   ABTEM_SRC=/path    must exist -- a typo must not silently downgrade to the
#                      container copy and quietly test something else
#   ABTEM_SRC=         (empty) force the container's own abTEM
ABTEM_SRC=${ABTEM_SRC%/}          # trailing slash breaks the prefix match later
if [ "$ABTEM_SRC_GIVEN" = 1 ] && [ -z "$ABTEM_SRC" ]; then
    ABTEM_MODE=container
elif [ -n "$ABTEM_SRC" ] && [ -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    ABTEM_MODE=branch
elif [ "$ABTEM_SRC_GIVEN" = 1 ]; then
    echo "ERROR: no abtem/__init__.py under ABTEM_SRC=$ABTEM_SRC" >&2
    echo "  Point it at a checkout, or pass ABTEM_SRC= (empty) to test the" >&2
    echo "  container's own abTEM instead." >&2
    exit 1
else
    ABTEM_MODE=container
    echo ">> no abTEM checkout at ${ABTEM_SRC:-<none>} -- testing the container's own abTEM"
    echo "   (export ABTEM_SRC=/path/to/abTEM to inject a branch instead)"
fi
if [ "$ABTEM_MODE" != branch ]; then
    ABTEM_SRC=""
else
    # Apptainer passes the host environment through, so exporting is enough. In
    # container mode we must NOT export an empty value: Python reads an empty
    # PYTHONPATH entry as the current directory, reviving the ./abtem trap.
    export APPTAINERENV_PYTHONPATH="$ABTEM_SRC"
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
if ! ABTEM_PROBE=$(apptainer exec --nv --bind "$BINDS" "$SIF" \
        python -P -c 'import abtem, importlib; _b = importlib.import_module("abtem.core.backend"); print(abtem.__file__ + "|" + abtem.__version__ + "|" + ("yes" if hasattr(_b, "ensure_cuda_cluster") and hasattr(_b, "is_gpu_dask_client") else "no"))' \
        | tail -n 1); then
    echo "ERROR: could not import abtem inside $SIF." >&2
    echo "  This is NOT (yet) the injection failing -- the container did not" >&2
    echo "  run, or abtem did not import at all. Check \$SIF exists and that" >&2
    echo "  the bind list covers it: $BINDS" >&2
    exit 1
fi
ABTEM_FILE=${ABTEM_PROBE%%|*}
_abtem_rest=${ABTEM_PROBE#*|}
ABTEM_VER=${_abtem_rest%%|*}
ABTEM_MG=${ABTEM_PROBE##*|}
case "$ABTEM_MODE" in
    branch)
        case "$ABTEM_FILE" in
            "$ABTEM_SRC"/*)
                echo "abtem in use: $ABTEM_VER  <- $ABTEM_FILE  (injected)" ;;
            *)
                echo "ERROR: the branch abTEM is not the one being imported." >&2
                echo "  imported: $ABTEM_FILE ($ABTEM_VER)" >&2
                echo "  expected: somewhere under $ABTEM_SRC" >&2
                echo "  The container's own abTEM won (editable, /opt/src/abTEM)." >&2
                echo "  The VERSION alone would not have shown this: the image" >&2
                echo "  stages its own abTEM checkout and may report the same one." >&2
                echo "  Check APPTAINERENV_PYTHONPATH and that \$ABTEM_SRC is in --bind." >&2
                exit 1 ;;
        esac ;;
    container)
        # No injection asked for, so any path is fine -- but the container's
        # abTEM must actually be able to do multi-GPU, or every check below
        # would be testing nothing and still reporting success.
        if [ "$ABTEM_MG" = yes ]; then
            echo "abtem in use: $ABTEM_VER  <- $ABTEM_FILE  (container's own, multi-GPU capable)"
        else
            echo "ERROR: the container's abTEM has no multi-GPU support." >&2
            echo "  imported: $ABTEM_FILE ($ABTEM_VER)" >&2
            echo "  ensure_cuda_cluster / is_gpu_dask_client are absent, so the" >&2
            echo "  checks below would test nothing while still passing." >&2
            echo "  Inject a checkout that has them, ABTEM_SRC=/path/to/abTEM," >&2
            echo "  or rebuild the image from one." >&2
            exit 1
        fi ;;
esac

# --nv exposes the GPUs; PYTHONPATH makes the container Python import the branch
# abTEM while dask-cuda/cupy/dask come from the container.
time apptainer exec --nv --bind "$BINDS" "$SIF" \
    python "$PAYLOAD_DIR/verify_multigpu.py" "$@"
