#!/bin/bash
# Quick correctness check in the debug QOS: 30 minutes max, up to 8 nodes,
# short queue wait. Use this to smoke-test a script before committing it to
# a long regular-QOS run — NOT for production (2 running jobs max).
#
# Charging is the same as regular (QOS factor 1.0), so keep it short.
#
# Usage:  sbatch debug_gpu.sbatch my_script.py [args...]
#         sbatch debug_gpu.sbatch            # runs the built-in smoke test
#
#SBATCH --job-name=eels_debug
#SBATCH --account=<project>_g          # <- replace; GPU account = _g suffix
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32
#SBATCH --gpus-per-node=1
#SBATCH --time=00:20:00                # debug hard limit is 00:30:00
#SBATCH --output=%x_%j.out

set -euo pipefail

IMAGE=${IMAGE:-ghcr.io/<username>/otherimage:latest}

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

if [ $# -gt 0 ]; then
    SCRIPT=$1; shift
    time srun podman-hpc run --rm --gpu \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        "$IMAGE" python "$SCRIPT" "$@"
    exit 0
fi

# --- built-in smoke test --------------------------------------------------
# `python -P` drops the CWD from sys.path so a stray ./gpaw directory cannot
# shadow the editable install (see README gotchas).
echo "== image identity =="
podman-hpc images --digests | grep -E "REPOSITORY|otherimage" || true

echo "== imports and versions =="
srun podman-hpc run --rm --gpu $MOUNTS "$IMAGE" python -P -c "
import gpaw, otherimage, torch, cupy
print('gpaw       ', gpaw.__version__)
print('otherimage ', getattr(otherimage, '__version__', 'n/a'))
print('torch      ', torch.__version__, 'cuda', torch.cuda.is_available())
print('device     ', torch.cuda.get_device_name(0))
print('cupy       ', cupy.__version__)
"

echo "== 4-rank MPI world (Cray MPICH injected) =="
srun --ntasks=4 --cpus-per-task=8 podman-hpc run --rm --mpi $MOUNTS \
    -e GPAW_MPI_BACKEND=cgpaw "$IMAGE" \
    python -P -c "from gpaw.mpi import world; print(world.rank, '/', world.size)"

echo "== extra-module test suite =="
srun podman-hpc run --rm $MOUNTS "$IMAGE" \
    bash -c 'cd /opt/src/gpaw && pytest -q gpaw/test/extra-module/'
