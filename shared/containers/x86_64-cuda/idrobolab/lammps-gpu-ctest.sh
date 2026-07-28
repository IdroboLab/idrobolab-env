#!/usr/bin/env bash
# lammps-gpu-ctest — run the LAMMPS force-style unit-test suite with the GPU
# package ON A GPU NODE.
#
# Each pair-style test carries a `TEST(PairStyle, gpu)` subtest that runs the
# /gpu (GPU-package) variant and compares its forces/energy to the style's
# reference data. That subtest activates only when Info::has_gpu_device() is
# true — i.e. on a real GPU — so it cannot run at `docker build` time. This is
# the GPU counterpart to the opt-in build-time CPU ctest (LAMMPS_RUN_TESTS=1):
# it builds the test binaries against a GPU-package LAMMPS here and runs ctest,
# exercising every built /gpu pair style against its reference.
#
# NOTE: LAMMPS has no KOKKOS-CUDA *device* unit test (the kokkos_omp subtests
# are CPU-only and skip when GPU support is enabled), so this covers the GPU
# package. For a quick KOKKOS-CUDA + GPU-package sanity run, use
# lammps-gpu-selftest instead.
#
#   apptainer exec --nv otherimage.sif lammps-gpu-ctest
#   apptainer exec --nv otherimage.sif lammps-gpu-ctest -R lj_cut   # scope
#
# HEAVY: clones LAMMPS and compiles liblammps + the GPU kernels + the test
# binaries on the node (a few minutes; no QUIP/KIM). Needs a GPU, nvcc/cmake/git
# (present in the -devel image) and network to clone LAMMPS.
#
# Env: LAMMPS_BRANCH (default stable), LAMMPS_GPU_CTEST_JOBS (default nproc).
# Extra args (e.g. -R <regex>, -E <regex>, -j N) are passed through to ctest.
set -uo pipefail

command -v nvcc >/dev/null 2>&1 || { echo "ERROR: nvcc not found (need the -devel image)"; exit 2; }
command -v cmake >/dev/null 2>&1 || { echo "ERROR: cmake not found"; exit 2; }
nvidia-smi -L >/dev/null 2>&1 || { echo "ERROR: no NVIDIA GPU visible (--nv / --gpus all)"; exit 2; }

INSTALL_DIR=${INSTALL_DIR:-/opt/software}
BR=${LAMMPS_BRANCH:-stable}
J=${LAMMPS_GPU_CTEST_JOBS:-$(nproc)}

# nvcc target from the GPU's compute capability (fallback sm_80)
cc=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')
case "$cc" in
  70) SM=sm_70 ;; 75) SM=sm_75 ;; 80) SM=sm_80 ;;
  86) SM=sm_86 ;; 89) SM=sm_89 ;; 90) SM=sm_90 ;;
  *)  SM=sm_80; echo ">> unknown compute cap '${cc:-?}' -> defaulting to sm_80" ;;
esac
echo ">> GPU compute cap ${cc:-?} -> $SM"; nvidia-smi -L

SRC=$(mktemp -d)/lammps
trap 'rm -rf "$(dirname "$SRC")"' EXIT
git clone --depth 1 -b "$BR" https://github.com/lammps/lammps.git "$SRC"
cd "$SRC"

# GPU package + the pair-style packages that carry /gpu variants; ENABLE_TESTING
# fetches googletest and builds the force-style test binaries. No KOKKOS-CUDA
# (no device unit test), no ML-QUIP/KIM (no /gpu pair style, and slow), so the
# build stays lean while covering the GPU-package styles.
cmake -S cmake -B build \
    -D CMAKE_BUILD_TYPE=Release -D CMAKE_PREFIX_PATH=${INSTALL_DIR}/fftw \
    -D BUILD_MPI=on -D BUILD_OMP=on -D BUILD_SHARED_LIBS=on -D LAMMPS_EXCEPTIONS=on \
    -D FFT=FFTW3 -D ENABLE_TESTING=on \
    -D PKG_GPU=on -D GPU_API=cuda -D GPU_ARCH="$SM" \
    -D PKG_EXTRA-PAIR=on -D PKG_MANYBODY=on -D PKG_MOLECULE=on -D PKG_KSPACE=on \
    -D PKG_EXTRA-FIX=on -D PKG_MISC=on -D PKG_REAXFF=on -D PKG_ML-SNAP=on \
    -D PKG_ML-IAP=on -D PKG_INTERLAYER=on -D PKG_MEAM=on -D PKG_OPENMP=on \
    || { echo "ERROR: cmake configure failed"; exit 1; }

cmake --build build -j"$J" || { echo "ERROR: build failed"; exit 1; }

export LD_LIBRARY_PATH="$SRC/build:${INSTALL_DIR}/fftw/lib:${LD_LIBRARY_PATH:-}"
echo ">> running the pair-style ctests — the PairStyle.gpu subtest runs on the GPU"
echo "   (grep the output for 'PairStyle.gpu' PASS/skip lines)"
# default to the pair-style tests (where the GPU subtest lives); extra args
# (incl. a different -R) are appended and win.
ctest --test-dir build --output-on-failure -R PairStyle "$@"
rc=$?
echo ">> ctest exit $rc"
exit $rc
