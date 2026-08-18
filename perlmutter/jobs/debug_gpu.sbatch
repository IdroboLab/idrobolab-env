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
#SBATCH --mem=220G                     # whole node in debug QOS
#SBATCH --time=00:20:00                # debug hard limit is 00:30:00
#SBATCH --output=%x_%j.out

set -euo pipefail

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
podman-hpc images --digests | grep -E "REPOSITORY|${IMAGE%%:*}" || true

echo "== imports and versions =="
srun podman-hpc run --rm --gpu $MOUNTS "$IMAGE" python -P -c "
import gpaw, torch, cupy
print('gpaw       ', gpaw.__version__)
# The other image's package ships in that image only; idrobolab carries gpaw
# (a fork branch, so its extra module is present), gpaw-weaver and abTEM instead. Report
# what is there rather than failing the smoke test on the wrong image.
for _name in ('otherimage', 'abtem', 'gpaw_weaver', 'pyslice'):
    try:
        _m = __import__(_name)
        print(f'{_name:11s}', getattr(_m, '__version__', 'present'))
    except ImportError:
        print(f'{_name:11s}', '-- not in this image')
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
