#!/bin/bash
# Preflight for the multi-GPU verification. NO venv is built.
#
# The container is read-only and its Python is itself a venv, so a nested
# `python -m venv --system-site-packages` cannot see the container's
# dask-cuda/cupy (it inherits only the *base* interpreter's site-packages, not
# the container venv's). Instead, the abTEM 'multi-gpu-support' branch is
# injected at run time via PYTHONPATH, shadowing the container's own abTEM
# (whatever was staged at build time -- the version does not discriminate);
# everything else (dask-cuda, cupy, dask) comes from the container.
#
# abTEM is pure Python with a committed abtem/_version.py, so no build/install
# step is needed -- PYTHONPATH is enough. This script just confirms the branch
# abTEM and the container's dask-cuda import together in one interpreter.
#
# Usage:
#   ABTEM_SRC=/path/to/abTEM ./setup_env.sh     # login node is fine
#
# Env vars:
#   SIF        container image (default $PROJECTS_BASE/software/containers/idrobolab.sif)
#   ABTEM_SRC  abTEM checkout to inject (optional). Unset/empty checks the
#              container's own abTEM instead.#
#   Image selection: SIF is the .sif path; IMAGE=<name> resolves to
#   $PROJECTS_BASE/software/containers/<name>.sif (default idrobolab),
#   matching the short-name form used by the Perlmutter launchers.


set -euo pipefail

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
# Optional: unset (or empty) checks the container's own abTEM, which the image
# installs editable from a staged checkout that may already carry multi-GPU.
if [ -n "${ABTEM_SRC+x}" ]; then ABTEM_SRC_GIVEN=1; else ABTEM_SRC_GIVEN=0; fi
ABTEM_SRC=${ABTEM_SRC-}
ABTEM_SRC=${ABTEM_SRC%/}

if [ "$ABTEM_SRC_GIVEN" = 1 ] && [ -z "$ABTEM_SRC" ]; then
    ABTEM_MODE=container
elif [ -n "$ABTEM_SRC" ] && [ -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    ABTEM_MODE=branch
elif [ -n "$ABTEM_SRC" ]; then
    echo "ERROR: no abtem/__init__.py under ABTEM_SRC=$ABTEM_SRC" >&2
    echo "       Point it at a checkout, or leave ABTEM_SRC unset to check" >&2
    echo "       the container's own abTEM." >&2
    exit 1
else
    ABTEM_MODE=container
fi

echo "container : $SIF"
if [ "$ABTEM_MODE" = branch ]; then
    echo "abtem src : $ABTEM_SRC (injected via PYTHONPATH -- no venv)"
else
    echo "abtem src : <none> -- checking the container's own abTEM"
fi

BINDS=""
for p in /projects /scratch /work "$ABTEM_SRC"; do
    [ -e "$p" ] && BINDS="${BINDS:+$BINDS,}$p"
done

if [ "$ABTEM_MODE" = branch ]; then export APPTAINERENV_PYTHONPATH="$ABTEM_SRC"; fi
APPTAINERENV_ABTEM_SRC="$ABTEM_SRC" \
apptainer exec --bind "$BINDS" "$SIF" python - <<'PY'
import abtem, dask, distributed, dask_cuda
from abtem.core.backend import is_gpu_dask_client  # multi-gpu branch present
print('abtem      ', abtem.__version__, '<-', abtem.__file__)
print('dask       ', dask.__version__)
print('distributed', distributed.__version__)
print('dask_cuda  ', dask_cuda.__version__)
try:
    import cupy
    print('cupy       ', cupy.__version__)
except Exception as e:  # cupy import can need a GPU node in some builds
    print('cupy       ', 'import deferred:', type(e).__name__)
# The old check here ('/abtem/' in abtem.__file__) passed for the CONTAINER's
# own editable abTEM as well, so it proved nothing. Assert the resolved path is
# actually under the checkout -- that is the only thing that distinguishes them,
# since both report the same version.
import os
src = os.environ.get('ABTEM_SRC', '').rstrip('/')
assert not src or os.path.realpath(abtem.__file__).startswith(os.path.realpath(src) + os.sep), \
    f'abTEM resolved to {abtem.__file__}, not under {src} -- the container won'
print('preflight OK: branch abTEM shadows the container, dask-cuda available')
PY

echo
echo "Preflight passed. Submit with:  ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch"
echo "(If you built the old overlay venv, it is unused now and can be removed:"
echo "   rm -rf \${MGPU_VENV:-\$SCRATCH_BASE/\$USER/venvs/abtem_mgpu} )"
