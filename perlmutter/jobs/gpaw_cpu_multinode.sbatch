#!/bin/bash
# GPAW / another image MPI job across MULTIPLE Perlmutter CPU nodes.
#
# Identical launch mechanism to the single-node script (srun + podman-hpc
# --mpi); only the node count and a couple of Slingshot knobs change. On
# Perlmutter the multi-node case is NOT a separate, riskier code path the way
# it is on Delta — the Cray MPICH swap-in is the same either way.
#
# Node: 2x AMD EPYC 7763 (Milan), 128 physical cores (256 logical), 512 GB.
# Charging: walltime x nodes x 1.0.  4 nodes x 2 h = 8 CPU node-hours.
#
# Usage:  sbatch gpaw_cpu_multinode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_mpi
#SBATCH --account=<project>            # <- replace; CPU account = NO _g suffix
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=128          # 512 ranks total
#SBATCH --cpus-per-task=2
#SBATCH --mem=440G                     # 512 GB CPU node (~86% as with 220G/256G)
#SBATCH --time=04:00:00
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
SCRIPT=${1:?usage: sbatch gpaw_cpu_multinode.sbatch script.py [args]}
shift

MOUNTS=""
for p in "${SCRATCH:-}" "${CFS:-}" "${HOME:-}"; do
    [ -n "$p" ] && [ -d "$p" ] && MOUNTS="$MOUNTS -v $p:$p"
done

# Run a cluster checkout instead of the baked-in code:
# MOUNTS="$MOUNTS -v $SCRATCH/code/gpaw:/opt/src/gpaw"

# Required for GPAW 26.7.0+ under an MPI launcher with plain `python`.
GPAW_ENV="-e GPAW_MPI_BACKEND=cgpaw -e OMP_NUM_THREADS=1"

MPICH_ENV="-e MPICH_SMP_SINGLE_COPY_MODE=CMA -e MPICH_OFI_STARTUP_CONNECT=1"

# Multi-node podman-hpc MPI sometimes fails PMPI init with a misleading
# "No space left on device" — NERSC's fix is to disable the VNI network
# feature. Harmless when not needed; drop it if you prefer to test without.
NETOPT="--network=no_vni"

echo "IMAGE=$IMAGE  nodes=$SLURM_JOB_NUM_NODES  ranks=$SLURM_NTASKS"
time srun --cpu-bind=cores \
    podman-hpc run --rm --mpi $NETOPT \
        $MOUNTS --workdir "$SLURM_SUBMIT_DIR" \
        $GPAW_ENV $MPICH_ENV \
        "$IMAGE" python "$SCRIPT" "$@"

# --- Scaling notes --------------------------------------------------------
# * GPAW rarely scales past a few hundred ranks on a single SCF; prefer
#   band/domain/kpt parallelisation tuning over simply adding nodes, and
#   check the "Parallelization" block GPAW prints in the .txt output.
# * If startup dominates at >512 ranks, try dropping MPICH_OFI_STARTUP_CONNECT
#   (it trades startup cost for steady-state latency, and the win flips).
# * Slingshot multithreaded hangs (mpich #7184): add
#   -e FI_CXI_RX_MATCH_MODE=hybrid
