#!/usr/bin/env bash
# Build Quantum ESPRESSO (qe-7.6) with GPU support inside an NVIDIA HPC SDK
# builder image, then stage ONLY the QE install + the runtime .so files it needs
# into /opt/qe-dist. The final container image COPY --from=s just that directory,
# so the multi-GB SDK never lands in the shipped image (NVIDIA's redistributable
# model). Runs in the `qe-builder` stage of the Dockerfile, NOT the final image.
#
# Backend: OpenACC + CUDA Fortran (nvfortran) — the mature NVIDIA path. FFT on
# GPU is cuFFT; CPU-side FFT is QE's internal FFTXlib (no external FFTW needed).
# MPI is the SDK's bundled OpenMPI (nvfortran-consistent). ScaLAPACK is off (GPU
# QE uses its own GPU eigensolvers) — matches QE's own --with-scalapack=no guidance.
#
# UNVERIFIED: built blind (no nvfortran/GPU/docker in the dev environment). This
# is a first-pass recipe; expect to iterate the NVHPC image tag, the MPI/lib
# paths, and the runtime-lib collection on a real build host.
#
# Env: QE_VERSION (default qe-7.6), QE_GPU_ARCHS (default sm_80; e.g. "sm_80;sm_90").
set -euo pipefail

QE_VERSION="${QE_VERSION:-qe-7.6}"
QE_GPU_ARCHS="${QE_GPU_ARCHS:-sm_80}"
SRC=/tmp/qe-src
DIST=/opt/qe-dist              # staged output the final image copies
PREFIX=/opt/software/qe        # the path QE will live at in the FINAL image

# --- locate the NVHPC compilers + bundled OpenMPI (layout varies by version) --
NVROOT="$(ls -d /opt/nvidia/hpc_sdk/Linux_x86_64/*/ 2>/dev/null | sort -V | tail -1)"
[ -n "$NVROOT" ] || { echo "ERROR: NVHPC SDK not found under /opt/nvidia/hpc_sdk"; exit 1; }
export PATH="${NVROOT}compilers/bin:${PATH}"
MPIBIN="$(dirname "$(find "${NVROOT}comm_libs" -name mpif90 -type f 2>/dev/null | sort -V | tail -1)")"
[ -n "$MPIBIN" ] && export PATH="${MPIBIN}:${PATH}"
command -v nvfortran >/dev/null || { echo "ERROR: nvfortran not on PATH"; exit 1; }
command -v mpif90    >/dev/null || { echo "ERROR: NVHPC mpif90 not on PATH"; exit 1; }
echo ">> nvfortran: $(command -v nvfortran) | mpif90: $(command -v mpif90)"

apt-get update
apt-get install -y --no-install-recommends git cmake ca-certificates patchelf
rm -rf /var/lib/apt/lists/*

rm -rf "$SRC"
git clone --depth 1 -b "$QE_VERSION" https://gitlab.com/QEF/q-e.git "$SRC"
cd "$SRC"

cmake -S . -B build \
    -D CMAKE_INSTALL_PREFIX="${PREFIX}" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_Fortran_COMPILER=mpif90 -D CMAKE_C_COMPILER=mpicc \
    -D QE_ENABLE_MPI=ON -D QE_ENABLE_OPENMP=ON \
    -D QE_GPU="openacc;cuda" -D QE_GPU_ARCHS="${QE_GPU_ARCHS}" \
    -D QE_ENABLE_SCALAPACK=OFF \
    -D QE_FFTW_VENDOR=Internal
cmake --build build -j"$(nproc)"
DESTDIR="" cmake --install build           # installs to $PREFIX inside the builder

# --- stage QE + its runtime shared libs into $DIST --------------------------
# Collect the transitive .so deps of every QE executable (ldd is recursive),
# excluding the core system libs (the final nvcr.io/nvidia/cuda image provides
# glibc/libgcc/libstdc++) and libcuda (the driver, injected at runtime by --nv).
mkdir -p "${DIST}/lib"
cp -a "${PREFIX}/." "${DIST}/"

for exe in "${DIST}"/bin/*.x; do
    [ -e "$exe" ] || continue
    ldd "$exe" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u | while read -r lib; do
    case "$lib" in
        */libc.so*|*/libm.so*|*/libmvec.so*|*/libpthread.so*|*/libdl.so*|*/librt.so*|\
        */libgcc_s.so*|*/libstdc++.so*|*/ld-linux*|*/libresolv*|*/libutil*|*/librt.so*) continue ;;
        */libcuda.so*) continue ;;
    esac
    cp -Lv "$lib" "${DIST}/lib/" 2>/dev/null || true
done

# rpath the executables and the staged libs to the FINAL install path so they
# find each other without an image-wide LD_LIBRARY_PATH (which would otherwise
# shadow the base image's own CUDA libs for GPAW etc.).
for f in "${DIST}"/bin/*.x "${DIST}"/lib/*.so*; do
    [ -e "$f" ] || continue
    patchelf --set-rpath "${PREFIX}/lib" "$f" 2>/dev/null || true
done

echo ">> staged QE runtime under ${DIST} ($(du -sh "${DIST}" 2>/dev/null | cut -f1))"
ls "${DIST}/bin" | grep -E 'pw\.x|ph\.x|cp\.x' || true
