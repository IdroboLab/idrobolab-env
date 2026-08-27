#!/bin/bash
# Multi-GPU verification for abTEM on a Perlmutter GPU node (4x A100 40 GB).
# Runs verify_multigpu.py inside another image's container (which ships
# dask-cuda), with the abTEM 'multi-gpu-support' branch injected via PYTHONPATH
# to shadow the container's own abTEM (no venv).
#
# No version number is quoted for the CONTAINER's abTEM anywhere below, on
# purpose: the image installs it EDITABLE from a staged checkout (Dockerfile:
# `pip install -e /opt/src/abTEM`), so which abTEM it carries depends on when
# the image was built -- the verification READMEs still say 1.0.9, the current
# Dockerfile stages an abTEM-main v1.1.0 checkout, and the branch is itself
# 1.1.0. `abtem.__version__` therefore CANNOT tell the two apart; only
# `abtem.__file__` can, which is what setup_env.sh and the precheck below
# assert on.
#
# Perlmutter counterpart of delta/verification/multigpu_abtem/multigpu_verify.sbatch.
# Same payload, byte for byte; only the launcher differs. The two differences
# that matter:
#   * the runtime is podman-hpc, not Apptainer -- there is no .sif, and
#     podman-hpc BIND-MOUNTS NOTHING by default (Apptainer inherits $HOME and
#     $PWD for free), so every path the job touches needs an explicit
#     -v host:container. See the mount block below.
#   * there is NO 8-GPU node type. Perlmutter GPU nodes are 1x AMD EPYC 7763
#     (64 physical / 128 logical cores, 256 GB) + 4x A100 40 GB -- 256 of the
#     nodes carry 80 GB parts via -C "gpu&hbm80g", but the GPU count is always
#     4. Delta's gpuA100x8 / gpuH200x8 variant blocks therefore have no
#     counterpart here, and GPU-count sweeps top out at 1,2,4.
#
# Usage:
#   . ../../env.sh              # PODMANHPC_ADDITIONAL_STORES -> shared CFS store
#   ../../helpers/update-image.sh otherimage   # pull/refresh the image (LOGIN node only)
#                                      # the argument matters: with none the
#                                      # script pulls idrobolab, a different
#                                      # (and much larger) image
#   export ABTEM_SRC=$SCRATCH/code/abTEM         # 'multi-gpu-support' checkout
#
#   Image selection (any of these):
#     IMAGE=idrobolab sbatch ...                 # short name -> ghcr.io/<username>/idrobolab:latest
#     IMAGE=idrobolab TAG=v3 sbatch ...          # short name, explicit tag
#     IMAGE=ghcr.io/other/img:tag sbatch ...     # full reference, used verbatim
#   Default is idrobolab; the short name matches `update-image.sh <name>`.
#   git -C "$ABTEM_SRC" switch multi-gpu-support
#   sbatch multigpu_verify.sbatch                # 4 GPUs, default checks
#   sbatch multigpu_verify.sbatch --timing       # + 1-GPU vs N-GPU wall clock
#   IMAGE=... ABTEM_SRC=... sbatch multigpu_verify.sbatch --gpus 2 --configs 16
#     ^ --gpus caps the dask CLUSTER, not the ALLOCATION: Slurm still hands over
#       (and charges for) the 4 GPUs requested below. To actually allocate fewer,
#       use the shared-QOS block further down.
#
# Submit from THIS directory: the shared payload dir is resolved relative to it
# (override with PAYLOAD_DIR).
#
# Login-node preflight (no GPU needed; proves the injection works before you
# spend an allocation on it) -- ./setup_env.sh does this with more reporting:
#   podman-hpc run --rm $GROUP_FLAGS -v "$ABTEM_SRC:$ABTEM_SRC" $PYPATH_FLAG \
#       ghcr.io/<username>/otherimage:latest \
#       python -P -c "import abtem; print(abtem.__version__, abtem.__file__)"
#   # abtem.__file__ MUST be under $ABTEM_SRC. If it is /opt/src/abTEM the
#   # container's own abTEM won and the checks below would be testing nothing --
#   # and the printed __version__ may be identical either way, so read the PATH,
#   # not the version. The job re-runs this check itself (see "injection
#   # precheck") and refuses to start.
#
# Charging: walltime x 1 node x QOS factor 1.0 = 1 GPU node-hour per hour.
#
#SBATCH --job-name=abtem_mgpu
#SBATCH --account=<project>_g               # override with sbatch -A; see jobs/README.md on _g
#SBATCH --constraint=gpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1            # one python process driving all 4 GPUs
#SBATCH --cpus-per-task=128            # 2 x floor(64/1) = every logical CPU
#SBATCH --gpus-per-node=4
#SBATCH --gpu-bind=none                # all 4 GPUs visible to the single task;
#                                      # dask-cuda does the per-worker pinning
#SBATCH --exclusive                    # 4 dask-cuda workers + a CUDA container
#                                      # want the node's full 256 GB
#SBATCH --mem=220G                     # full 256 GB GPU node
#SBATCH --time=00:10:00
#SBATCH --output=%x_%j.out
#
# QOS: `debug` caps at 30 minutes and 8 nodes, queues fast, and is charged at
# exactly the same rate as `regular` (both QOS factor 1.0) -- free speed for a
# ten-minute check. Limits: 5 queued / 2 running. For anything longer (a heavy
# --supercell, --timing on a big workload, or a hung-cluster debug session)
# switch to `#SBATCH --qos=regular` and raise --time; regular allows 48 h.
# Over 00:30:00 on debug the job is REJECTED at submit time, not truncated.
#
# Cheaper 1-2 GPU variant: the verification also runs with `--gpus 1` / `--gpus 2`
# (fewer coverage checks, obviously). NERSC policy asks those to use the shared
# QOS, which is prorated -- 0.25 node-hr/h for 1 GPU, 0.5 for 2. It is not a
# one-line edit: --exclusive AND --gpus-per-node=4 both have to go, or the job
# still holds (and is charged for) a whole node's GPUs.
#   #SBATCH --qos=shared
#   #SBATCH --gpus=2 --cpus-per-task=64
#   ...and DELETE the --exclusive, --gpus-per-node=4 AND --mem lines above. Do
#   NOT replace --mem with a smaller value: on the shared queue Slurm derives a
#   core count from --mem too, takes the larger, and rejects anything that is
#   not exactly 32 logical cores per GPU. The slice's memory share comes with
#   the cores. See jobs/README.md.

# No `module reset` here: Perlmutter has no such command (the Delta script opens
# with one) and the site profile is already in force. No
# --constraint="scratch&projects" either -- that is a Delta filesystem
# constraint; on Perlmutter -C selects the node type.
set -euo pipefail

# Preserve supplementary group membership inside the container. podman runs
# rootless in a user namespace, and by default only the PRIMARY group is mapped:
# every supplementary group -- which on NERSC is how project access to
# /global/cfs/cdirs/<project> is granted -- is dropped. The symptom is a path
# your shell can enter but the container cannot:
#
#   Error: crun: chdir to `/global/cfs/cdirs/<project>/...`: Permission denied
#
# It bites collaborators for whom the project group is supplementary while
# working fine for whoever has it as their primary group, which makes it look
# like a per-user permission problem. `keep-groups` (crun only, rootless only)
# passes them through. Set PODMAN_GROUP_FLAGS= to disable if it ever misbehaves.
GROUP_FLAGS=${PODMAN_GROUP_FLAGS---group-add keep-groups}

# Under `sbatch`, Slurm runs a spool COPY of this script, so BASH_SOURCE points
# at the spool dir (payload absent). Use the submit dir; fall back to the script
# dir for `bash` runs. Submit from this launcher's directory.
HERE="${SLURM_SUBMIT_DIR:-}"
[ -n "$HERE" ] || HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The Python payloads are shared with Delta and live in
# shared/verification/multigpu_abtem/; only the launchers are per-cluster, so
# the two clusters cannot drift. Resolved relative to this directory (the
# Perlmutter launchers sit at the same depth as Delta's, so the same ../../../
# works); override with PAYLOAD_DIR if you keep the payloads elsewhere.
PAYLOAD_DIR=${PAYLOAD_DIR:-$HERE/../../../shared/verification/multigpu_abtem}
if [ -d "$PAYLOAD_DIR" ]; then
    PAYLOAD_DIR=$(cd "$PAYLOAD_DIR" && pwd)
fi
if [ ! -f "$PAYLOAD_DIR/verify_multigpu.py" ]; then
    echo "ERROR: verify_multigpu.py not found in $PAYLOAD_DIR" >&2
    echo "Submit from perlmutter/verification/multigpu_abtem/, or set PAYLOAD_DIR." >&2
    exit 1
fi

# OTHERIMAGE_IMAGE is exported by ../../env.sh; the literal is the fallback for
# a shell that never sourced it.
# Image selection. Accepts either a bare name -- `IMAGE=idrobolab` -- or a full
# reference (`ghcr.io/user/img:tag`, or one pinned by @sha256:...). A value with
# no "/" is treated as a short name and expanded against the same registry and
# owner update-image.sh uses, so `./update-image.sh idrobolab` and
# `IMAGE=idrobolab sbatch ...` always name the same image. TAG applies only to
# the short-name form; a full reference carries its own.
IMAGE=${IMAGE:-${IDROBOLAB_IMAGE:-idrobolab}}
case "$IMAGE" in
    */*) : ;;                       # already a full reference, use verbatim
    *)   IMAGE="ghcr.io/${IMAGE_OWNER:-<username>}/${IMAGE}:${TAG:-latest}" ;;
esac

# abTEM 'multi-gpu-support' checkout. It is injected via PYTHONPATH to shadow the
# container's own abTEM -- no venv: the container's Python is itself a venv, so
# a nested venv (--system-site-packages inherits only the *base* interpreter's
# packages) cannot see the container's dask-cuda/cupy. abTEM is pure Python with
# a committed abtem/_version.py, so there is no build or install step.
# ${SCRATCH:-$HOME} only so `set -u` cannot abort with a confusing message on a
# shell where SCRATCH is unset; on Perlmutter it is /pscratch/sd/<initial>/<user>.
if [ -n "${ABTEM_SRC+x}" ]; then ABTEM_SRC_GIVEN=1; else ABTEM_SRC_GIVEN=0; fi
ABTEM_SRC=${ABTEM_SRC-${SCRATCH:-$HOME}/code/abTEM}

# Which abTEM gets tested. ABTEM_SRC names a checkout to inject over the
# container's own copy. Leaving it out is legitimate: the image installs abTEM
# editable from a staged checkout that may already carry the multi-GPU work, and
# testing that copy is a real thing to want.
#
#   ABTEM_SRC unset    the default path if it exists, else the container's abTEM
#   ABTEM_SRC=/path    must exist -- a typo must not silently downgrade to the
#                      container copy and quietly test something else
#   ABTEM_SRC=         (empty) force the container's own abTEM
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
if [ "$ABTEM_MODE" != branch ]; then ABTEM_SRC=""; fi

# Only set when injecting. An EMPTY PYTHONPATH would be worse than none: Python
# reads an empty entry as the current directory, reviving the ./abtem shadowing
# trap. Unquoted at the use site, same pre-split-flags idiom as $MOUNTS.
PYPATH_FLAG=""
if [ "$ABTEM_MODE" = branch ]; then PYPATH_FLAG="-e PYTHONPATH=$ABTEM_SRC"; fi
if [ "$ABTEM_MODE" = branch ]; then ABTEM_SRC=$(cd "$ABTEM_SRC" && pwd); fi

# --- mounts ---------------------------------------------------------------
# podman-hpc mounts nothing by default. Each path is mounted at its own host
# path (-v P:P) so absolute paths mean the same thing on both sides and can be
# handed straight to the container command line.
#
# The $ABTEM_SRC mount is MANDATORY and is the easiest thing to get wrong:
# PYTHONPATH alone points at a path that does not exist inside the container,
# Python silently skips it, the container's own abTEM wins, and every
# multi-GPU check would then be testing code that has no multi-GPU support.
# add_mount() therefore always covers it (directly or via a parent mount), and
# the precheck below proves it at run time.
MOUNTS=""
MOUNTED=""
add_mount() {
    local p=${1:-} m
    [ -n "$p" ] && [ -d "$p" ] || return 0
    p=$(cd "$p" && pwd)
    for m in $MOUNTED; do
        # Already mounted, or contained in something already mounted. An
        # IDENTICAL destination is a hard podman error ("duplicate mount
        # destination"); a nested one merely shadows part of its parent.
        # Skipping both is correctness first, tidiness second.
        case "$p" in "$m" | "$m"/*) return 0 ;; esac
    done
    MOUNTED="$MOUNTED $p"
    MOUNTS="$MOUNTS -v $p:$p"
}
# Broad filesystems first so the specific paths below collapse into them.
add_mount "${SCRATCH:-}"
add_mount "${CFS:-}"
add_mount "${HOME:-}"
add_mount "$HERE"          # submit dir: job stdout, dask worker spill dir
add_mount "$PAYLOAD_DIR"   # the shared verify_multigpu.py
add_mount "$ABTEM_SRC"     # mandatory -- see the note above
# (paths with spaces would break the MOUNTED word-split loop; none exist on
# Perlmutter's filesystems, and podman -v would need escaping anyway. Paths are
# resolved LOGICALLY -- `cd && pwd`, not `pwd -P` -- so a symlinked $ABTEM_SRC
# is mounted under the same name PYTHONPATH uses, which is what we want. The
# residual hole: a symlink inside a mounted tree whose target lies outside
# $SCRATCH, $CFS and $HOME would not be reachable in the container. Nothing on
# Perlmutter normally does that; not verified on-cluster.)

# Passed through for the payload's environment report (section 0) -- these are
# exactly the SLURM_* names it prints. Bare `-e VAR` forwards the host value (an
# unset one is simply not set in the container).
# CUDA_VISIBLE_DEVICES is the fifth name it prints and is deliberately NOT
# forwarded:
# podman-hpc's --gpu maps devices into the container itself, and a host-ordered
# value could mask GPUs the container was given. Let the container see all four
# and let dask-cuda assign one per worker.
SLURM_ENV="-e SLURM_JOB_ID -e SLURM_JOB_PARTITION -e SLURM_JOB_GPUS -e SLURM_GPUS_ON_NODE"

# The image defaults OMP_NUM_THREADS=1. dask-cuda runs one single-threaded
# worker per GPU (4 processes), so allow 16 threads each: 4 x 16 = the node's 64
# physical cores, with no BLAS oversubscription. The real work is on the GPUs.
THREAD_ENV="-e OMP_NUM_THREADS=16 -e OPENBLAS_NUM_THREADS=16"

# Image provenance -- record this digest alongside any result you keep.
echo "== image =="
podman-hpc images --digests | grep -E "REPOSITORY|${IMAGE%%:*}" || \
    echo "(not listed: source ../../env.sh for the shared CFS store, or pull" \
         "it on a LOGIN node with ../../helpers/update-image.sh otherimage)"

echo "IMAGE=$IMAGE"
echo "abtem_src=$ABTEM_SRC (via PYTHONPATH, mounted at the same path)"
echo "payload=$PAYLOAD_DIR/verify_multigpu.py"
echo "GPUs requested: ${SLURM_GPUS_ON_NODE:-?}   node=$(hostname)"
echo "mounts:$MOUNTS"

# --- injection precheck ---------------------------------------------------
# Cheap (seconds, no GPU needed) and it fails loudly instead of producing a
# green-looking run of the wrong abTEM. `python -P` drops the CWD from sys.path
# so a stray ./abtem directory cannot shadow the import; PYTHONPATH is still
# honoured.
#
# The probe PRINTS the resolved path and this script compares it, rather than
# having the container exit(3) and testing $?. Two reasons: the status would
# have to survive podman-hpc's wrapper before bash sees it, and -- the real
# point -- a nonzero status is ambiguous. "Image not visible on the compute
# node", "abtem does not import at all" and "the WRONG abtem imported" are
# three different problems with three different fixes, and reporting all of
# them as a broken injection sends the reader to the wrong place. Same idiom as
# benchmark_haadf.sbatch.
#
# No srun: the batch script already runs on the first allocated compute node,
# so podman-hpc runs there directly -- the `podman-hpc images` call above relies
# on the same thing, and this probe needs no GPU. `tail -n 1` because only the
# last stdout line is ours. $MOUNTS is unquoted on purpose (pre-split flags).
if ! ABTEM_PROBE=$(podman-hpc run --rm $GROUP_FLAGS $MOUNTS \
        $PYPATH_FLAG "$IMAGE" \
        python -P -c 'import abtem, importlib; _b = importlib.import_module("abtem.core.backend"); print(abtem.__file__ + "|" + abtem.__version__ + "|" + ("yes" if hasattr(_b, "ensure_cuda_cluster") and hasattr(_b, "is_gpu_dask_client") else "no"))' \
        | tail -n 1); then
    echo "ERROR: could not import abtem inside $IMAGE." >&2
    echo "  This is NOT (yet) the injection failing: the container did not run," >&2
    echo "  or abtem did not import at all. Check the image is visible from a" >&2
    echo "  COMPUTE node -- source ../../env.sh (shared CFS store), then" >&2
    echo "  \`podman-hpc images\`. A locally BUILT image also needs" >&2
    echo "  \`podman-hpc migrate <tag>\`; a pulled one is migrated for you." >&2
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
                echo "  Check that BOTH -v \$ABTEM_SRC:\$ABTEM_SRC and" >&2
                echo "  -e PYTHONPATH=\$ABTEM_SRC are on the run line." >&2
                exit 1 ;;
        esac ;;
    container)
        # No injection was asked for, so any path is fine -- but the container's
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

# --- run ------------------------------------------------------------------
# --gpu exposes the A100s (podman-hpc's equivalent of Apptainer's --nv).
# --workdir keeps the CWD on a mounted, writable path -- dask workers put their
# spill directory in the CWD. $MOUNTS/$THREAD_ENV/$SLURM_ENV are intentionally
# unquoted: they are pre-split option lists, not single words.
#
# -e PYTHONPATH REPLACES the image's own PYTHONPATH (currently
# /opt/software/lammps/python, the LAMMPS python module) rather than prepending
# to it -- the container never sees the host's variable, so there is nothing to
# append to. Nothing this payload imports lives there. A payload that does need
# lammps should pass "$ABTEM_SRC:/opt/software/lammps/python" instead.
# "$@" is forwarded to the payload, so --timing / --gpus / --configs / --rmm-pool
# work straight off the sbatch command line.
time srun --cpu-bind=none \
    podman-hpc run --rm $GROUP_FLAGS --gpu \
        $MOUNTS --workdir "$HERE" \
        $PYPATH_FLAG \
        $THREAD_ENV $SLURM_ENV \
        "$IMAGE" python "$PAYLOAD_DIR/verify_multigpu.py" "$@"

# --- if it misbehaves -----------------------------------------------------
# * `Killed` / SIGKILL during cluster bring-up = host-memory OOM. This script
#   asks for a whole exclusive node (256 GB), so that should not happen here;
#   it does happen if you drop --exclusive, move to the shared QOS, or run the
#   script with `bash` (which ignores every #SBATCH line). Section 0 prints the
#   cgroup limit the payload sees -- note that under podman that is the
#   *container's* cgroup; with no --memory passed to podman-hpc it should
#   report the node total.
# * Fewer workers than GPUs -> check `--gpus-per-node=4` really landed
#   (nvidia-smi -L inside the container) -- dask-cuda makes one worker per
#   visible GPU.
# * A /dev/shm-related failure during bring-up would point at podman's default
#   shared-memory size (documented as 64 MB); `--shm-size=<n>g` on the
#   `podman-hpc run` line is the knob. Whether these dask-cuda workers ever hit
#   it is NOT observed and not verified on Perlmutter -- listed only so the
#   option is known.
# * Interactive equivalent (4-GPU shell, interactive QOS: 4 h, <=4 nodes):
#     ../../jobs/interactive_gpu.sh          # salloc + a shell in the container
#   or, from the allocation shell, the same checks by hand:
#     podman-hpc run --rm $GROUP_FLAGS --gpu -v $HOME:$HOME -v $SCRATCH:$SCRATCH \
#         -v $ABTEM_SRC:$ABTEM_SRC -e PYTHONPATH=$ABTEM_SRC $IMAGE \
#         python $PAYLOAD_DIR/verify_multigpu.py
#   $HOME is in that list because the repo checkout -- hence $PAYLOAD_DIR --
#   usually lives there, and podman-hpc mounts NOTHING by default: leave it out
#   and you get "can't open file .../verify_multigpu.py". Append --no-cluster
#   for a per-GPU smoke test only; that skips the distribution checks, so it is
#   not a substitute for the job above.
# * See ./README.md for what each check means, for the dask / dask-cuda version
#   knot that the container build resolves, and for the full troubleshooting list.
