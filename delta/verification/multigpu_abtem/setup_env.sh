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
#   SIF        container image (default $PROJECTS_BASE/software/containers/otherimage_delta.sif)
#   ABTEM_SRC  abTEM checkout on the 'multi-gpu-support' branch (required)

set -euo pipefail

SIF=${SIF:-${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif}
ABTEM_SRC=${ABTEM_SRC:?export ABTEM_SRC=<path to abTEM 'multi-gpu-support' checkout>}

if [ ! -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    echo "ERROR: abTEM checkout not found at $ABTEM_SRC" >&2
    exit 1
fi

echo "container : $SIF"
echo "abtem src : $ABTEM_SRC (injected via PYTHONPATH -- no venv)"

BINDS=""
for p in /projects /scratch /work "$ABTEM_SRC"; do
    [ -e "$p" ] && BINDS="${BINDS:+$BINDS,}$p"
done

APPTAINERENV_PYTHONPATH="$ABTEM_SRC" \
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
assert '/abtem/' in abtem.__file__ or abtem.__file__.rstrip('/').endswith('abtem/__init__.py')
print('preflight OK: branch abTEM shadows the container, dask-cuda available')
PY

echo
echo "Preflight passed. Submit with:  ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch"
echo "(If you built the old overlay venv, it is unused now and can be removed:"
echo "   rm -rf \${MGPU_VENV:-\$SCRATCH/venvs/abtem_mgpu} )"
