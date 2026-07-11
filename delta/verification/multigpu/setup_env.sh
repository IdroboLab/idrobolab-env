#!/bin/bash
# Build the overlay venv used by multigpu_verify.sbatch.
#
# The container already provides dask-cuda + cupy + the full stack (see
# containers/otherimage/otherimage_delta.def). It only ships abTEM 1.0.9, which
# has NO multi-GPU support, so this venv layers the abTEM 'multi-gpu-support'
# branch on top -- nothing else. Once that branch is released and pinned in
# requirements-delta.txt, this step becomes unnecessary.
#
# The branch installs cleanly against the container's dask 2026.7.0 (its
# dask!=2026.1.1 pin is satisfied), so there is no version gymnastics and no
# internet requirement when ABTEM_SRC is a local checkout -- run it on a login
# OR a compute node.
#
# Usage:
#   ABTEM_SRC=$SCRATCH/code/abTEM ./setup_env.sh
#
# Env vars:
#   SIF        container image (default $SCRATCH/containers/otherimage_delta.sif)
#   MGPU_VENV  venv location    (default $SCRATCH/venvs/abtem_mgpu)
#   ABTEM_SRC  abTEM checkout on the 'multi-gpu-support' branch (required)

set -euo pipefail

: "${SCRATCH:?run 'module reset' first so SCRATCH is set, or export it}"
SIF=${SIF:-$SCRATCH/containers/otherimage_delta.sif}
MGPU_VENV=${MGPU_VENV:-$SCRATCH/venvs/abtem_mgpu}
ABTEM_SRC=${ABTEM_SRC:?export ABTEM_SRC=<path to abTEM 'multi-gpu-support' checkout>}

echo "container : $SIF"
echo "venv      : $MGPU_VENV"
echo "abtem src : $ABTEM_SRC"

apptainer exec --bind /scratch,/projects,/work "$SIF" bash -euo pipefail -c "
    python -m venv --system-site-packages '$MGPU_VENV'
    '$MGPU_VENV/bin/pip' install --upgrade pip
    # abTEM branch, editable. Its deps (dask 2026.7, cupy, dask-cuda, ...) are
    # already in the container and inherited via --system-site-packages, so this
    # only shadows the container's abtem 1.0.9 with the branch.
    '$MGPU_VENV/bin/pip' install -e '$ABTEM_SRC'
    echo '--- versions in overlay venv ---'
    '$MGPU_VENV/bin/python' - <<'PY'
import abtem, dask, distributed, dask_cuda, cupy
from abtem.core.backend import is_gpu_dask_client  # noqa: F401 -- multi-gpu branch present
print('abtem      ', abtem.__version__, '(', abtem.__file__, ')')
print('dask       ', dask.__version__)
print('distributed', distributed.__version__)
print('dask_cuda  ', dask_cuda.__version__)
print('cupy       ', cupy.__version__)
print('multi-gpu support: OK (is_gpu_dask_client importable)')
PY
"

echo
echo "Overlay venv ready at $MGPU_VENV"
echo "Submit with:  MGPU_VENV=$MGPU_VENV ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch"
