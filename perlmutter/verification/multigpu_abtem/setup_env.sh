#!/bin/bash
# Preflight for the multi-GPU abTEM verification on Perlmutter. NO venv is built.
#
# Run this on a LOGIN node before submitting multigpu_verify.sbatch. It answers
# the one question that is expensive to get wrong in a queued job: does the
# 'multi-gpu-support' branch of abTEM actually shadow the container's own
# abTEM, with the container's dask/dask-cuda still importable in the SAME
# interpreter?
#
# Deliberately no version number anywhere below: the image installs abTEM
# EDITABLE from a staged checkout (Dockerfile: `pip install -e /opt/src/abTEM`),
# so which abTEM it carries depends on when the image was built -- the READMEs
# still say 1.0.9, the current Dockerfile stages a v1.1.0 checkout. What the
# checks assert is therefore the PATH the import resolves to, which is exact
# whatever the image ships.
#
# Why no venv: the container's Python is itself a venv, so a nested
# `python -m venv --system-site-packages` cannot see the container's
# dask-cuda/cupy (it inherits only the *base* interpreter's site-packages, not
# the container venv's). And note that "the image is read-only" -- the Delta
# argument -- does NOT hold here: podman gives every instance a writable
# overlay, so a `pip install` inside one appears to work. It is discarded when
# the container exits (`--rm`), never reaches the next `podman-hpc run`, and
# persisting it would mean rebuilding the image, so the conclusion is the same.
# Instead the branch checkout is injected at run time via PYTHONPATH;
# everything else (dask, distributed, dask-cuda, cupy) comes from the
# container. abTEM is pure Python with a committed abtem/_version.py, so there
# is no build or install step -- PYTHONPATH is enough.
#
# Perlmutter vs Delta, the part that bites: the runtime here is podman-hpc, not
# Apptainer, and *podman-hpc bind-mounts nothing by default*. Apptainer gives
# you $HOME and $PWD for free; podman does not. So the injection needs BOTH
#     -e PYTHONPATH=$ABTEM_SRC     (what Delta does with APPTAINERENV_PYTHONPATH)
#     -v $ABTEM_SRC:$ABTEM_SRC     (mandatory here, and easy to forget)
# Without the mount, PYTHONPATH names a path that does not exist inside the
# container, the import silently falls through to the container's own abTEM,
# and every multi-GPU "check" then tests code that has no multi-GPU support.
# That failure mode is invisible unless you look -- which is exactly why the
# check below asserts on abtem.__file__ (and, secondarily, on a symbol the
# multi-GPU work adds), and prints the resolved path either way.
#
# Usage:
#   . ../../env.sh                              # optional; sets the image store
#   ABTEM_SRC=$SCRATCH/code/abTEM ./setup_env.sh
#
# Env vars:
#   ABTEM_SRC  abTEM checkout on the 'multi-gpu-support' branch (required)
#   IMAGE      container image (default: $OTHERIMAGE_IMAGE from env.sh, else
#              ghcr.io/<username>/otherimage:latest)

set -euo pipefail

# This script is run directly (`./setup_env.sh`), never through sbatch, so
# BASH_SOURCE is the real file -- no spool-copy dance like the .sbatch files.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# env.sh exports OTHERIMAGE_IMAGE (and the CFS image store); honour it when the
# user sourced it, but stay usable when they did not.
IMAGE=${IMAGE:-${OTHERIMAGE_IMAGE:-ghcr.io/<username>/otherimage:latest}}
ABTEM_SRC=${ABTEM_SRC:?export ABTEM_SRC=<path to abTEM 'multi-gpu-support' checkout>}

# --- guards ---------------------------------------------------------------

command -v podman-hpc >/dev/null 2>&1 || {
    echo "ERROR: podman-hpc not on PATH." >&2
    echo "       Perlmutter uses podman-hpc, not Apptainer -- there is no .sif." >&2
    echo "       Run this on a Perlmutter login node." >&2
    exit 1
}

if [ ! -f "$ABTEM_SRC/abtem/__init__.py" ]; then
    echo "ERROR: abTEM checkout not found at $ABTEM_SRC" >&2
    echo "       Expected \$ABTEM_SRC/abtem/__init__.py. Clone abTEM and" >&2
    echo "       'git switch multi-gpu-support', e.g. under \$SCRATCH/code/abTEM." >&2
    exit 1
fi

# Resolve symlinks NOW, on the host. podman mounts the physical directory, and
# the in-container assertion compares realpath(abtem.__file__) against this
# string -- if the two disagree only by a symlink hop the assertion would fail
# for the wrong reason. `pwd -P` removes that whole class of confusion.
ABTEM_SRC=$(cd "$ABTEM_SRC" && pwd -P)

# The launchers resolve the shared payloads relative to themselves; check the
# same path here so a missing/moved payload surfaces before you queue a job.
# (Perlmutter launchers sit at the same depth as Delta's, so ../../../ works.)
PAYLOAD_DIR=${PAYLOAD_DIR:-$HERE/../../../shared/verification/multigpu_abtem}
if [ -d "$PAYLOAD_DIR" ]; then PAYLOAD_DIR=$(cd "$PAYLOAD_DIR" && pwd); fi
if [ ! -f "$PAYLOAD_DIR/verify_multigpu.py" ]; then
    echo "ERROR: verify_multigpu.py not found in $PAYLOAD_DIR" >&2
    echo "       The Python payloads are shared with Delta and live in" >&2
    echo "       shared/verification/multigpu_abtem/. Set PAYLOAD_DIR if you" >&2
    echo "       keep them elsewhere." >&2
    exit 1
fi

# Non-fatal hints. Neither is required for THIS check (a login-node podman-hpc
# reads its own local store happily), but both bite later, in the job.
if [ -z "${PODMANHPC_ADDITIONAL_STORES:-}" ]; then
    echo "NOTE: PODMANHPC_ADDITIONAL_STORES is unset -- the job will search" >&2
    echo "      only your own squash store, not the project's shared one on" >&2
    echo "      CFS. Source ../../env.sh to add it (read via /dvs_ro)." >&2
fi
# `podman-hpc images` prints repository and tag in separate columns, so match on
# the repository part only (a digest-pinned ref is trimmed at the '@' first).
# The listing is captured BEFORE matching, and matched with a here-string
# rather than a pipe: under `set -o pipefail`, `podman-hpc images | grep -q`
# can report failure merely because grep -q exits at the first match and the
# producer then takes SIGPIPE -- i.e. this NOTE would fire for an image that is
# in fact present. Advisory either way: a miss may just be a formatting
# difference, and the run below is the real authority.
IMAGE_REPO=${IMAGE%%@*}
IMAGE_REPO=${IMAGE_REPO%:*}
IMAGE_LIST=$(podman-hpc images 2>/dev/null || true)
if ! grep -qF -- "$IMAGE_REPO" <<<"$IMAGE_LIST"; then
    echo "NOTE: '$IMAGE_REPO' not visible in \`podman-hpc images\`." >&2
    echo "      Pull it into the shared store first:  ../../update-image.sh otherimage" >&2
    echo "      (or: podman-hpc pull $IMAGE). Pulls need a LOGIN node." >&2
fi

echo "image     : $IMAGE"
echo "abtem src : $ABTEM_SRC (injected via PYTHONPATH -- no venv)"
echo "payloads  : $PAYLOAD_DIR"
echo

# --- the check ------------------------------------------------------------
#
# Deliberately WITHOUT --gpu: login nodes have no GPU, and asking podman-hpc for
# one there is pointless. Consequence: the cupy import may legitimately fail
# here, so it is tolerated (same as the Delta preflight). The GPU node, via
# multigpu_verify.sbatch, is what actually exercises cupy and the cluster.
#
# -i keeps stdin attached so `python -` can read the heredoc (podman detaches
# stdin by default; Apptainer does not -- another small runtime difference).
# -P drops the CWD from sys.path so a stray directory named after a package
# cannot shadow an editable install. It does NOT affect PYTHONPATH, so the
# abTEM injection is unaffected.
# Only $ABTEM_SRC is mounted: this check needs nothing else. The launchers
# mount considerably more ($SCRATCH, $CFS, $HOME, the payload dir) because the
# actual runs read and write there.
# -e PYTHONPATH REPLACES the image's own value (the Dockerfile sets it to
# /opt/software/lammps/python) rather than prepending to it. Nothing in abTEM,
# dask or the verification payloads imports lammps, and the .sbatch launchers
# pass the exact same flag -- so preflight and job stay identical, which is the
# point. If a payload ever does need the image's entries, prepend inside the
# container instead of widening this line, and change the launchers too.
podman-hpc run --rm -i \
    -v "$ABTEM_SRC:$ABTEM_SRC" \
    -e PYTHONPATH="$ABTEM_SRC" \
    -e ABTEM_SRC_EXPECTED="$ABTEM_SRC" \
    "$IMAGE" python -P - <<'PY'
import os
import sys

expect = os.path.realpath(os.environ["ABTEM_SRC_EXPECTED"])
problems = []

# --- 1. did the branch abTEM actually shadow the container's copy? --------
# Asserted, not assumed: PYTHONPATH shadowing is a sys.path-order effect and it
# is silent when it does not happen (you just get the container's abTEM).
import abtem
where = os.path.realpath(abtem.__file__)
print("abtem      ", getattr(abtem, "__version__", "?"), "<-", where)
if not (where == expect or where.startswith(expect + os.sep)):
    problems.append(
        "abtem imported from {}\n"
        "        instead of the checkout under {}.\n"
        "        The container's own abTEM won -- almost always a missing\n"
        "        -v {}:{} (podman-hpc mounts nothing by default), so\n"
        "        PYTHONPATH pointed at a path that does not exist inside the\n"
        "        container.".format(where, expect, expect, expect))

# --- 2. does the imported abTEM carry the multi-GPU code? -----------------
# is_gpu_dask_client is added by the multi-GPU work -- abTEM main (and 1.0.9)
# has no multi-GPU code at all. Necessary, but NOT sufficient as a branch
# fingerprint: the image stages a local abTEM checkout, and if that checkout
# was cut from a branch that already carried the symbol, this import would
# succeed against the container's copy too. Check 1 is the authoritative
# proof; this one catches "right path, wrong branch".
try:
    from abtem.core.backend import is_gpu_dask_client  # noqa: F401
    print("abtem multi-gpu  is_gpu_dask_client present (branch code active)")
except ImportError as exc:
    problems.append(
        "abtem.core.backend.is_gpu_dask_client is missing ({}).\n"
        "        Either the shadowing failed (see above) or the checkout is\n"
        "        not on the 'multi-gpu-support' branch:\n"
        "        git -C {} switch multi-gpu-support".format(exc, expect))

# --- 3. the container half of the stack -----------------------------------
import dask
import distributed
print("dask       ", dask.__version__)
print("distributed", distributed.__version__)

try:
    import dask_cuda
    print("dask_cuda  ", dask_cuda.__version__)
except ModuleNotFoundError:
    # Not installed = an image problem; no GPU node will fix it.
    problems.append(
        "dask_cuda is not installed in the container. The multi-GPU path\n"
        "        needs it (see the README's dask/dask-cuda version knot).")
except Exception as exc:
    # Some dask-cuda versions touch NVML at import; whether this one does on a
    # GPU-less login node is not something to assert from here. Report, do not
    # fail -- the GPU-node job is the authority.
    print("dask_cuda   import deferred:", type(exc).__name__, "-", exc)
    print("            (installed, but import needs a GPU node -- recheck there)")

try:
    import cupy
    print("cupy       ", cupy.__version__)
except Exception as exc:
    # Expected on a login node: no GPU, no driver. Not a failure.
    print("cupy        import deferred:", type(exc).__name__)

# --- verdict --------------------------------------------------------------
if problems:
    print()
    for p in problems:
        print("FAIL:", p)
    sys.exit(1)

print()
print("preflight OK: branch abTEM shadows the container, dask stack available")
PY

# --- next step ------------------------------------------------------------
# Perlmutter GPU nodes are 4x A100 and nothing else -- there is no 8-GPU node
# here, so unlike Delta (gpuA100x8 / gpuH200x8) the GPU-count sweep tops out at
# 1/2/4 and the launchers have no 8-GPU variant to switch to.
echo
echo "Preflight passed. Edit the --account line (GPU accounts carry the _g"
echo "suffix, e.g. -A <project>_g), then submit FROM THIS DIRECTORY -- the launcher"
echo "resolves the shared payload dir relative to \$SLURM_SUBMIT_DIR:"
echo
echo "    cd $HERE && ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch"
echo
echo "Add --timing for a 1-vs-4 GPU wall-clock comparison; IMAGE=... sbatch ..."
echo "overrides the image. The HAADF scaling benchmarks are"
echo "benchmark_haadf.sbatch (explicit cluster) and benchmark_haadf_auto.sbatch"
echo "(automatic dask.multi-gpu path)."
