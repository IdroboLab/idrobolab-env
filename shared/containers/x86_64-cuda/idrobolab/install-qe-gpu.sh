#!/usr/bin/env bash
# Build Quantum ESPRESSO (qe-7.6) with GPU support inside an NVIDIA HPC SDK
# builder image, then stage ONLY the QE install + the runtime .so files it needs
# into /opt/qe-dist. The final container image COPY --from=s just that directory,
# so the multi-GB SDK never lands in the shipped image (NVIDIA's redistributable
# model). Runs in the `qe-builder` stage of the Dockerfile, NOT the final image.
#
# Backend: OpenACC + CUDA Fortran (nvfortran) — the mature NVIDIA path. FFT on
# GPU is cuFFT; CPU-side FFT is QE's internal FFTXlib (no external FFTW needed).
# MPI is MPICH: pw.x links libmpi.so.12 like the rest of the image, and the Fortran
# binding library libmpifort.so.12 comes from an MPICH built here with nvfortran;
# the SDK's bundled Open MPI is not REDIST and is not used. ScaLAPACK is
# off (GPU QE uses its own GPU eigensolvers) — matches QE's own --with-scalapack=no guidance.
#
# The GPU-less docker build sandbox drives the two CUDA workarounds below: the
# bundled CUDA toolkit has to be pinned explicitly (nvfortran otherwise resolves
# it from the absent driver) and the libcuda stub has to go on the link path.
# UNVERIFIED: the MPICH build with gcc/nvfortran and the QE build against it have
# not run on a build host, and pw.x has not been executed on a GPU node, so the staged
# .so set and the rpaths are unproven.
#
# Env: QE_VERSION (default qe-7.6), QE_GPU_ARCHS (default sm_80; e.g. "sm_80;sm_90"),
# MPICH_VERSION (required: the Dockerfile passes its MPICH_VERSION),
# SOURCES_DIR (set by the Dockerfile: where the source archive of QE is kept).
set -euo pipefail

QE_VERSION="${QE_VERSION:-qe-7.6}"
QE_GPU_ARCHS="${QE_GPU_ARCHS:-sm_80}"
SRC=/tmp/qe-src
DIST=/opt/qe-dist              # staged output the final image copies
PREFIX=/opt/software/qe        # the path QE will live at in the FINAL image

# --- locate the NVHPC compilers ----------------------------------------------
NVROOT="$(ls -d /opt/nvidia/hpc_sdk/Linux_x86_64/*/ 2>/dev/null | sort -V | tail -1)"
[ -n "$NVROOT" ] || { echo "ERROR: NVHPC SDK not found under /opt/nvidia/hpc_sdk"; exit 1; }
export PATH="${NVROOT}compilers/bin:${PATH}"
for c in nvc nvc++ nvfortran; do
    command -v "$c" >/dev/null || { echo "ERROR: $c not on PATH"; exit 1; }
done
echo ">> nvfortran: $(command -v nvfortran)"

apt-get update
apt-get install -y --no-install-recommends git cmake ca-certificates patchelf wget make python3 gcc g++
rm -rf /var/lib/apt/lists/*

# --- MPICH, Fortran bindings built with nvfortran ----------------------------
# The Dockerfile's MPICH (same version, device and netmod) with nvfortran as its Fortran
# compiler, so that libmpifort matches the nvfortran that compiles QE. Only its
# libmpifort.so.12 is staged with QE (stage-qe-libs.sh): pw.x takes libmpi.so.12 from the
# image's MPICH. C and C++ are gcc/g++: nvc cannot build the embedded libfabric (its
# fi_* symbols end up missing from libfabric.so), and the Fortran-dependent parts of
# libmpifort (name mangling, string lengths, .TRUE.) come from configure's nvfortran probes.
# No mpi_f08: its C wrappers would use gcc's view of ISO_Fortran_binding.h, not nvfortran's
# descriptor layout; QE uses mpif.h / the mpi module.
MPICH_VERSION="${MPICH_VERSION:?MPICH_VERSION is not set}"
MPICH_PREFIX=/opt/mpich-nvhpc
run_logged() {  # run_logged LOG CMD...: keep the log out of the build output, tail it on failure
    local log="$1"; shift
    "$@" > "$log" 2>&1 || {
        echo "!! failed: $*"; tail -n 100 "$log"
        [ -f config.log ] && { echo "===== config.log ====="; tail -n 100 config.log; }
        return 1
    }
}
mkdir -p /tmp/mpich-build
cd /tmp/mpich-build
wget -q "https://github.com/pmodels/mpich/releases/download/v${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz"
tar xzf "mpich-${MPICH_VERSION}.tar.gz"
cd "mpich-${MPICH_VERSION}"
run_logged /tmp/mpich-configure.log ./configure --prefix="${MPICH_PREFIX}" \
    CC=gcc CXX=g++ F77=nvfortran FC=nvfortran \
    --with-device=ch4:ofi --with-libfabric=embedded \
    --enable-shared --disable-static --disable-f08
grep -E 'values of Fortran logicals' /tmp/mpich-configure.log || true   # informational
run_logged /tmp/mpich-make.log make -j"$(nproc)"
run_logged /tmp/mpich-install.log make install
cp COPYRIGHT "${MPICH_PREFIX}/MPICH-COPYRIGHT"
cd /
rm -rf /tmp/mpich-build
export PATH="${MPICH_PREFIX}/bin:${PATH}"
export LD_LIBRARY_PATH="${MPICH_PREFIX}/lib:${LD_LIBRARY_PATH:-}"   # for ldd in stage-qe-libs.sh
[ "$(command -v mpif90)" = "${MPICH_PREFIX}/bin/mpif90" ] || { echo "ERROR: mpif90 is $(command -v mpif90)"; exit 1; }
mpichversion | tee /tmp/mpichversion.txt
grep -q nvfortran /tmp/mpichversion.txt || { echo "ERROR: MPICH was not built with nvfortran"; exit 1; }
ls -l "${MPICH_PREFIX}"/lib/libmpi.so.12 "${MPICH_PREFIX}"/lib/libmpifort.so.12   # libmpifort ships, libmpi does not
echo ">> mpif90: $(command -v mpif90)"
# mpicc compiles QE's C with nvc, so that QE's OpenMP C and Fortran use one compiler's runtime.
export MPICH_CC=nvc

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

# QE is GPL-2.0-or-later: keep the source as built (the submodules cmake initialised
# included) in $SOURCES_DIR, which the sources image collects. Nothing here reaches the
# final image.
bash "$(dirname "$0")/keep-git-source.sh" "$SRC" "$QE_VERSION"

# --- stage QE + its runtime shared libs into $DIST --------------------------
# stage-qe-libs.sh copies the transitive .so deps of every QE executable.
# It fails the build on any NVIDIA HPC SDK file that is not a REDIST* file.
# Those are the only SDK files the SDK license lets the image redistribute.
# It also fails on a library with an NVIDIA name found outside the SDK.
# It also sets the rpath of the QE executables, and of the libs that are not
# SDK files, to the FINAL install path.
cp -a "${PREFIX}/." "${DIST}/"
cp "${MPICH_PREFIX}/MPICH-COPYRIGHT" "${DIST}/MPICH-COPYRIGHT"
bash "$(dirname "$0")/stage-qe-libs.sh" /opt/nvidia/hpc_sdk "${DIST}" "${PREFIX}/lib"

echo ">> staged QE runtime under ${DIST} ($(du -sh "${DIST}" 2>/dev/null | cut -f1))"
ls "${DIST}/bin" | grep -E 'pw\.x|ph\.x|cp\.x' || true
