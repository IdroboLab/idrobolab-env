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
# The GPU-less docker build sandbox drives the two CUDA workarounds below: the
# bundled CUDA toolkit has to be pinned explicitly (nvfortran otherwise resolves
# it from the absent driver) and the libcuda stub has to go on the link path.
# This script now runs to completion on the build host (configure, build,
# install, staging). What is still UNVERIFIED is runtime: pw.x has not been
# executed on a GPU node, so the staged .so set and the rpaths are unproven.
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

# --- CUDA Fortran preflight (nvfortran in a GPU-less build sandbox) ----------
# nvfortran resolves WHICH bundled CUDA toolkit to use from the driver it
# detects. There is no driver in the build sandbox (nvfortran reports driver
# version 0), so on a single-CUDA SDK image (-devel-cuda12.6) asking for a
# compute capability fails with
#     nvfortran-Error-CUDA version X.Y is not available in this installation.
#     A CUDA toolkit matching the current driver version (0) or a supported
#     older version was not installed with this HPC SDK.
# QE's cmake surfaces that only as "nvfortran CUDA related option check failed"
# (QE gitlab #423). Fix: pin the toolkit with -gpu=cudaX.Y, which QE's cmake
# emits from NVFORTRAN_CUDA_VERSION. Probe it here so a mismatch fails in
# seconds with the real compiler message rather than as an opaque cmake abort.
GPU_CC="$(echo "${QE_GPU_ARCHS}" | tr ';' ',' | sed 's/sm_/cc/g')"
SDK_CUDA="$(ls -d "${NVROOT}"cuda/*/ 2>/dev/null | sed 's#.*/cuda/##; s#/##' \
            | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
echo ">> SDK CUDA toolkits: $(ls "${NVROOT}"cuda 2>/dev/null | tr '\n' ' ')"

# The CUDA driver API (libcuda.so.1) ships in the driver, not the toolkit, and
# is absent here, so put the SDK's stub on the link path — same fix the LAMMPS
# build needs. -rpath-link is what resolves INDIRECT deps; -L alone does not.
STUB_LIB="$(find "${NVROOT}" -name 'libcuda.so' -path '*stubs*' 2>/dev/null | sort -V | tail -1 || true)"
STUBS=""
STUB_LDFLAGS=()
if [ -n "${STUB_LIB}" ]; then
    STUBS="$(dirname "${STUB_LIB}")"
    ln -sf "${STUBS}/libcuda.so" "${STUBS}/libcuda.so.1"
    export LIBRARY_PATH="${LIBRARY_PATH:-}:${STUBS}"
    STUB_LDFLAGS=( -L"${STUBS}" "-Wl,-rpath-link,${STUBS}" )
    echo ">> CUDA driver stub on link path: ${STUBS}"
fi

printf 'program p\nend program p\n' > /tmp/qe-cuda-probe.f90
probe() {  # compile AND link, mirroring cmake's check_fortran_compiler_flag
    mpif90 "$@" "${STUB_LDFLAGS[@]}" /tmp/qe-cuda-probe.f90 -o /tmp/qe-cuda-probe 2>&1
}
CUDA_PIN=""
if [ -n "${SDK_CUDA}" ] && PROBE_OUT="$(probe -cuda "-gpu=cuda${SDK_CUDA}" "-gpu=${GPU_CC}")"; then
    CUDA_PIN="${SDK_CUDA}"
    echo ">> CUDA Fortran probe OK: -cuda -gpu=cuda${SDK_CUDA} -gpu=${GPU_CC}"
elif PROBE_OUT="$(probe -cuda "-gpu=${GPU_CC}")"; then
    echo ">> CUDA Fortran probe OK: -cuda -gpu=${GPU_CC} (SDK default toolkit)"
else
    echo "ERROR: nvfortran cannot compile+link CUDA Fortran for -gpu=${GPU_CC}."
    echo "--- nvfortran output --------------------------------------------"
    echo "${PROBE_OUT}"
    echo "--- nvfortran -V ------------------------------------------------"
    nvfortran -V 2>&1 | head -3
    echo "--- SDK CUDA toolkits -------------------------------------------"
    ls "${NVROOT}"cuda 2>/dev/null || true
    echo "-----------------------------------------------------------------"
    echo "Hint: use a -devel-cuda_multi SDK image (more toolkit versions), or"
    echo "      set QE_GPU_ARCHS to an arch the bundled toolkit supports."
    exit 1
fi

CMAKE_EXTRA=()
if [ -n "${CUDA_PIN}" ]; then
    CMAKE_EXTRA+=( -D "NVFORTRAN_CUDA_VERSION=${CUDA_PIN}" )
fi
if [ -n "${STUBS}" ]; then
    CMAKE_EXTRA+=( -D "CMAKE_EXE_LINKER_FLAGS=-L${STUBS} -Wl,-rpath-link,${STUBS}" )
fi

if ! cmake -S . -B build \
    -D CMAKE_INSTALL_PREFIX="${PREFIX}" \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_Fortran_COMPILER=mpif90 -D CMAKE_C_COMPILER=mpicc \
    -D QE_ENABLE_MPI=ON -D QE_ENABLE_OPENMP=ON \
    -D QE_GPU="openacc;cuda" -D QE_GPU_ARCHS="${QE_GPU_ARCHS}" \
    -D QE_ENABLE_SCALAPACK=OFF \
    -D QE_FFTW_VENDOR=Internal \
    "${CMAKE_EXTRA[@]}"; then
    # cmake >= 3.26 (ubuntu 24.04 ships 3.28) logs try_compile output to
    # CMakeConfigureLog.yaml and never writes the CMakeError.log that QE's
    # error message points at, so dump the log that actually exists.
    echo "!! cmake configure FAILED — tail of the try_compile log follows:"
    for f in build/CMakeFiles/CMakeConfigureLog.yaml build/CMakeFiles/CMakeError.log; do
        if [ -f "$f" ]; then echo "===== $f ====="; tail -n 200 "$f"; fi
    done
    exit 1
fi
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
