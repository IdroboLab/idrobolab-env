#!/bin/bash
# GPAW / another image MPI job across MULTIPLE cpu-partition nodes.
#
# *** UNTESTED ON DELTA — verify the paths below on a node first (see the
#     "VERIFY ON DELTA" block and jobs/README.md) ***
#
# Since the Dec-2025 RH9 upgrade Delta supports only Cray MPICH, launched
# with `srun` (no mpirun). To get native Slingshot-11 performance from the
# container we use the Apptainer "hybrid"/MPICH-ABI model, exactly as HPE
# Cray EX sites do (NASA Athena, NERSC, CSCS):
#
#   * bind the host Cray MPICH ABI libs ($CRAY_MPICH_DIR/lib-abi-mpich,
#     which ships libmpi.so.12) OVER the container's /opt/software/mpich/lib
#     (first on the container's LD_LIBRARY_PATH, so the Cray lib wins);
#   * bind the whole /opt/cray tree so Cray's dependencies (PMI, libfabric
#     + cxi provider, GTL) resolve via their built-in RUNPATH;
#   * inject ONLY the few /usr/lib64 system libs that libcxi/libfabric need
#     via APPTAINER_CONTAINLIBS — this copies just those named files into
#     /.singularity.d/libs. We do NOT bind /usr/lib64 and do NOT put it on
#     LD_LIBRARY_PATH: that would shadow the container's newer glibc and
#     break every binary. (Host RHEL9 glibc 2.34 < container Ubuntu-24.04
#     glibc 2.39, so the host Cray libs load fine against the newer glibc.)
#
# Usage:  sbatch gpaw_cpu_multinode.sbatch my_gpaw_script.py [args...]
#
#SBATCH --job-name=gpaw_mpi
#SBATCH --account=<project>-delta-cpu   # <- replace; see `accounts` command
#SBATCH --partition=cpu
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=128           # 1 rank/core, full nodes
#SBATCH --cpus-per-task=1
#SBATCH --exclusive
#SBATCH --mem=0                         # all node memory
#SBATCH --time=02:00:00
#SBATCH --constraint="scratch"
#SBATCH --output=%x_%j.out

module reset                            # loads cray-mpich (default); sets $WORK/$SCRATCH; before set -u (Lmod)
module load cray-mpich                  # ensure CRAY_MPICH_DIR/MPICH_DIR are set
set -euo pipefail

SIF=${SIF:-${SCRATCH:?set SIF, or run where 'module reset' exports SCRATCH}/containers/otherimage_delta.sif}
SCRIPT=${1:?usage: sbatch gpaw_cpu_multinode.sbatch script.py [args]}
shift

# --- Cray MPICH injection (MPICH ABI: libmpi.so.12) -----------------------
: "${CRAY_MPICH_DIR:?cray-mpich module not loaded — check 'module list'}"

CRAY_ABI="${CRAY_MPICH_DIR}/lib-abi-mpich"        # Cray libmpi.so.12 (ABI drop-in)
CRAY_PE_LIB="/opt/cray/pe/lib64"                  # libpmi*, symlinks
LIBFABRIC_LIB="$(ls -d /opt/cray/libfabric/*/lib64 2>/dev/null | tail -1)"

# ---------------------------------------------------------------------------
# VERIFY ON DELTA before first real run (paths/sonames vary by module version):
#   module show cray-mpich; echo "$CRAY_MPICH_DIR"
#   ls "$CRAY_ABI"/libmpi.so.12            # confirm the ABI lib is here
#   ls -d /opt/cray/libfabric/*/lib64
#   srun --mpi=list                        # confirm pmi2 (else try pmix / cray_shasta)
#   ldd /usr/lib64/libcxi.so.1             # get EXACT sonames for CONTAINLIBS below
# ---------------------------------------------------------------------------

# Only these specific host libs are injected (copied into /.singularity.d/libs),
# never the rest of /usr/lib64. Adjust the soname versions per the ldd above.
export APPTAINER_CONTAINLIBS="/usr/lib64/libcxi.so.1,/usr/lib64/libjson-c.so.5,/usr/lib64/libnl-3.so.200,/usr/lib64/libnl-route-3.so.200,/usr/lib64/libcurl.so.4,/usr/lib64/libtinfo.so.6"

# Container search path: container MPICH dir FIRST (now the bound Cray ABI),
# then Cray dep dirs and the CONTAINLIBS destination. /usr/lib64 is absent by
# design, so host glibc never shadows the container.
export APPTAINERENV_LD_LIBRARY_PATH="/opt/software/mpich/lib:${CRAY_PE_LIB}:${LIBFABRIC_LIB}:/.singularity.d/libs"

# Cray MPICH runtime knobs (containers have no /dev/xpmem -> CMA for intra-node).
export APPTAINERENV_MPICH_SMP_SINGLE_COPY_MODE=CMA
export APPTAINERENV_MPICH_OFI_STARTUP_CONNECT=1   # helps all-to-all-heavy startup
# If you hit Slingshot multithreaded hangs (mpich issue #7184), also try:
# export APPTAINERENV_FI_CXI_RX_MATCH_MODE=hybrid

BINDS="${CRAY_ABI}:/opt/software/mpich/lib,/opt/cray:/opt/cray"
for p in /projects /scratch /work; do [ -d "$p" ] && BINDS="$BINDS,$p"; done

# Run a cluster checkout instead of the baked-in code:
# BINDS="$BINDS,$SCRATCH/code/gpaw:/opt/src/gpaw"

export OMP_NUM_THREADS=1                # pure MPI

echo "SIF=$SIF  ranks=$((SLURM_JOB_NUM_NODES * ${SLURM_NTASKS_PER_NODE:-0}))"
echo "Cray ABI: $CRAY_ABI  libfabric: $LIBFABRIC_LIB"
time srun --mpi=pmi2 apptainer exec --bind "$BINDS" "$SIF" \
    python "$SCRIPT" "$@"

# --- Correctness fallback (no Slingshot injection) ------------------------
# If the injection misbehaves and `srun --mpi=list` shows pmi2, the
# container's OWN MPICH also works (correct results, TCP transport, slower):
#   unset APPTAINER_CONTAINLIBS APPTAINERENV_LD_LIBRARY_PATH
#   BINDS2=""; for p in /projects /scratch /work; do [ -d "$p" ] && \
#       BINDS2="${BINDS2:+$BINDS2,}$p"; done
#   srun --mpi=pmi2 apptainer exec --bind "$BINDS2" "$SIF" python "$SCRIPT" "$@"
