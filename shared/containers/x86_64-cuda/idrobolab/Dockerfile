# ============================================================================
# idrobolab — computational-materials + microscopy-analysis container.
# GPAW (DFT) + abTEM (multislice) + ptyrad (ptychography) + nionswift (EM data)
# + ML potentials (fairchem, orb-models) + phonons (phonopy, hiphive) +
# pymatgen + dask + jupyterlab, on CUDA 12.9 / Python 3.12 / x86_64.
#
# fairchem-core pins torch~=2.13.0, so this image uses torch 2.13.0. fairchem v2
# needs no torch-geometric wheels.
#
# Build (host with docker/podman, after ./prepare_build_context.sh):
#   ./publish.sh   # builds and pushes ghcr.io/idrobolab/idrobolab:<VERSION>-rc
#                  # (:latest is set by release.sh)
#   -> apptainer build idrobolab.sif docker://ghcr.io/idrobolab/idrobolab:latest   (Delta)
#   -> podman-hpc pull …                                                (Perlmutter)
#
# Layer-cached: compiled libs + GPU wheels are early; requirements + the three
# editable source trees are copied late so a pin/source change rebuilds only
# from there.
#
# Sources of the GPL, LGPL, MPL and CDDL software compiled or downloaded here are kept in
# /opt/sources by the stages that fetch them (qe-builder, builder). The `sources` stage
# collects them with SHA256SUMS and publish.sh pushes it as <image>:<tag>-sources
# (`podman build --target sources`); the main image carries only SHA256SUMS.
# ============================================================================
# ===== Quantum ESPRESSO GPU builder stage (NVIDIA HPC SDK / nvfortran) =======
# QE's GPU path needs nvfortran, which lives only in the multi-GB NVHPC SDK.
# Build QE in the SDK image here; the final stage COPY --from=s only the QE
# install + its runtime .so files (install-qe-gpu.sh), so the SDK never reaches
# the shipped image. UNVERIFIED — built blind (no nvfortran/GPU/docker in the dev
# env); the NVHPC image tag, MPI/lib paths and runtime-lib collection will likely
# need iteration on a real build host. Override the tag: --build-arg NVHPC_IMAGE=.
ARG NVHPC_IMAGE=nvcr.io/nvidia/nvhpc:25.1-devel-cuda12.6-ubuntu24.04
ARG QE_VERSION=qe-7.6
ARG QE_GPU_ARCHS=sm_80
FROM ${NVHPC_IMAGE} AS qe-builder
ARG QE_VERSION
ARG QE_GPU_ARCHS
ENV SOURCES_DIR=/opt/sources
COPY install-qe-gpu.sh stage-qe-libs.sh keep-git-source.sh /tmp/
RUN QE_VERSION="${QE_VERSION}" QE_GPU_ARCHS="${QE_GPU_ARCHS}" bash /tmp/install-qe-gpu.sh

# ===== builder stage (full -devel toolchain; discarded after the split) ======
# Compiles the whole stack; nothing here ships — the slim -runtime final stage
# below COPY --from=s only the built artifacts, dropping the nvcc/headers/static
# CUDA libs + the apt build toolchain.
# The CUDA version of this base (both stages) equals the CUDA of the pip-installed libraries
# (torch cu129 wheels, CuPy): a process loads one cuBLAS, so a mismatch fails at the first
# cuSOLVER call.
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04 AS builder

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ENV INSTALL_DIR=/opt/software \
    SOURCES_DIR=/opt/sources \
    VIRTUAL_ENV=/opt/venv \
    PIP_NO_CACHE_DIR=1 \
    PIP_RETRIES=10 \
    PIP_TIMEOUT=120 \
    UV_HTTP_TIMEOUT=180 \
    UV_NO_CACHE=1
ENV PATH=/opt/venv/bin:/opt/software/mpich/bin:/usr/local/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/software/mpich/lib:/opt/software/libxc/lib:/opt/software/libvdwxc/lib:/opt/software/fftw/lib:/opt/software/scalapack/lib:/opt/software/elpa/lib:/opt/software/magma/lib

# SOURCES.txt and docs/THIRD-PARTY.md name the versions of the software with a source duty
# (these ARGs; QE_VERSION before the qe-builder stage; LAMMPS_BRANCH in the LAMMPS block at
# the end of this stage; kim-api and QUIP in LAMMPS's cmake files): update them together.
ARG MPICH_VERSION=4.3.2
ARG FFTW_VERSION=3.3.10
ARG SCALAPACK_VERSION=2.2.0
ARG LIBXC_VERSION=7.0.0
ARG LIBVDWXC_VERSION=0.5.0
ARG ELPA_VERSION=2024.05.001
ARG MAGMA_VERSION=2.7.2
ARG BADER_VERSION=1.05
ARG ARCH_FLAGS="-O3 -march=x86-64-v3"

# --- system packages (build toolchain + Qt6 runtime for the nionswift GUI) ---
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential gfortran \
        autoconf automake libtool m4 cmake pkg-config \
        git wget curl ca-certificates bzip2 \
        python3 python3.12 python3.12-venv python3.12-dev \
        libopenblas-dev \
        libfabric-dev libhwloc-dev libevent-dev \
        libssl-dev \
        xvfb libgl1 libegl1 libxkbcommon0 libdbus-1-3 libfontconfig1 \
        libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
        libxcb-randr0 libxcb-render-util0 libxcb-shape0; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# --- Bader charge analysis (Henkelman) — precompiled static binary ----------
# GPL-3.0-or-later, so the source from the same site is kept in /opt/sources. The binary and
# source tarball both carry the banner "Version ${BADER_VERSION} <date>"; the build fails when
# either lacks it, so the source matches the binary.
RUN set -eux; mkdir -p ${SOURCES_DIR}; \
    BADER_URL=https://theory.cm.utexas.edu/henkelman/code/bader/download; \
    curl -fsSL ${BADER_URL}/bader_lnx_64.tar.gz | tar xz -C /usr/local/bin; \
    chmod +x /usr/local/bin/bader; \
    curl -fsSL -o ${SOURCES_DIR}/bader-${BADER_VERSION}.tar.gz ${BADER_URL}/bader.tar.gz; \
    grep -aq "Version ${BADER_VERSION} " /usr/local/bin/bader; \
    tar xzOf ${SOURCES_DIR}/bader-${BADER_VERSION}.tar.gz | grep -a "Version ${BADER_VERSION} " >/dev/null

# --- MPICH (ch4:ofi; MPICH ABI libmpi.so.12) --------------------------------
RUN set -eux; cd /tmp; \
    wget -q https://github.com/pmodels/mpich/releases/download/v${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz; \
    tar xzf mpich-${MPICH_VERSION}.tar.gz; cd mpich-${MPICH_VERSION}; \
    ./configure --prefix=${INSTALL_DIR}/mpich-${MPICH_VERSION} \
        --with-device=ch4:ofi --with-libfabric=embedded \
        --enable-shared --disable-static; \
    make -j "$(nproc)"; make install; \
    ln -sfn ${INSTALL_DIR}/mpich-${MPICH_VERSION} ${INSTALL_DIR}/mpich; \
    cd /; rm -rf /tmp/mpich-${MPICH_VERSION}*

# --- FFTW -------------------------------------------------------------------
RUN set -eux; cd /tmp; \
    wget -q https://www.fftw.org/fftw-${FFTW_VERSION}.tar.gz; \
    cp fftw-${FFTW_VERSION}.tar.gz ${SOURCES_DIR}/; \
    tar xzf fftw-${FFTW_VERSION}.tar.gz; cd fftw-${FFTW_VERSION}; \
    ./configure --prefix=${INSTALL_DIR}/fftw-${FFTW_VERSION} \
        CFLAGS="${ARCH_FLAGS}" --enable-shared --disable-static \
        --enable-threads --enable-openmp --enable-mpi \
        --enable-sse2 --enable-avx --enable-avx2; \
    make -j "$(nproc)"; make install; \
    ln -sfn ${INSTALL_DIR}/fftw-${FFTW_VERSION} ${INSTALL_DIR}/fftw; \
    cd /; rm -rf /tmp/fftw-${FFTW_VERSION}*

# --- ScaLAPACK --------------------------------------------------------------
RUN set -eux; cd /tmp; \
    wget -q -O scalapack-${SCALAPACK_VERSION}.tar.gz \
        https://github.com/Reference-ScaLAPACK/scalapack/archive/refs/tags/v${SCALAPACK_VERSION}.tar.gz; \
    tar xzf scalapack-${SCALAPACK_VERSION}.tar.gz; cd scalapack-${SCALAPACK_VERSION}; \
    mkdir build && cd build; \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/scalapack-${SCALAPACK_VERSION} \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_C_COMPILER=mpicc -DCMAKE_Fortran_COMPILER=mpifort \
        -DCMAKE_C_FLAGS="${ARCH_FLAGS}" \
        -DCMAKE_Fortran_FLAGS="-O3 -march=x86-64-v3 -fallow-argument-mismatch" \
        -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF \
        -DBLAS_LIBRARIES=/usr/lib/x86_64-linux-gnu/libopenblas.so \
        -DLAPACK_LIBRARIES=/usr/lib/x86_64-linux-gnu/libopenblas.so; \
    make -j "$(nproc)"; make install; \
    ln -sfn ${INSTALL_DIR}/scalapack-${SCALAPACK_VERSION} ${INSTALL_DIR}/scalapack; \
    cd /; rm -rf /tmp/scalapack-${SCALAPACK_VERSION}*

# --- Python venv + build toolchain ------------------------------------------
RUN set -eux; \
    python3.12 -m venv /opt/venv; \
    pip install --upgrade pip setuptools wheel

# --- libxc (+ pylibxc) ------------------------------------------------------
RUN set -eux; cd /tmp; \
    wget -q https://gitlab.com/libxc/libxc/-/archive/${LIBXC_VERSION}/libxc-${LIBXC_VERSION}.tar.gz; \
    cp libxc-${LIBXC_VERSION}.tar.gz ${SOURCES_DIR}/; \
    tar xzf libxc-${LIBXC_VERSION}.tar.gz; cd libxc-${LIBXC_VERSION}; \
    autoreconf -i; \
    ./configure --prefix=${INSTALL_DIR}/libxc-${LIBXC_VERSION} \
        CFLAGS="${ARCH_FLAGS} -fPIC" --enable-shared --disable-static --enable-fortran; \
    make -j "$(nproc)"; make install; \
    pip install numpy; \
    CMAKE_POLICY_VERSION_MINIMUM=3.5 pip install --no-build-isolation .; \
    ln -sfn ${INSTALL_DIR}/libxc-${LIBXC_VERSION} ${INSTALL_DIR}/libxc; \
    cd /; rm -rf /tmp/libxc-${LIBXC_VERSION}*

# --- libvdwxc ---------------------------------------------------------------
RUN set -eux; cd /tmp; \
    wget -q https://gitlab.com/libvdwxc/libvdwxc/-/archive/${LIBVDWXC_VERSION}/libvdwxc-${LIBVDWXC_VERSION}.tar.gz; \
    cp libvdwxc-${LIBVDWXC_VERSION}.tar.gz ${SOURCES_DIR}/; \
    tar xzf libvdwxc-${LIBVDWXC_VERSION}.tar.gz; cd libvdwxc-${LIBVDWXC_VERSION}; \
    (sh autogen.sh || autoreconf -i); \
    mkdir build && cd build; \
    ../configure --prefix=${INSTALL_DIR}/libvdwxc-${LIBVDWXC_VERSION} \
        CC=mpicc FC=mpifort \
        CFLAGS="${ARCH_FLAGS}" FCFLAGS="-g -O2 -march=x86-64-v3" \
        CPPFLAGS="-I${INSTALL_DIR}/fftw/include" LDFLAGS="-L${INSTALL_DIR}/fftw/lib" \
        --with-fftw3; \
    make -j "$(nproc)"; make install; \
    ln -sfn ${INSTALL_DIR}/libvdwxc-${LIBVDWXC_VERSION} ${INSTALL_DIR}/libvdwxc; \
    cd /; rm -rf /tmp/libvdwxc-${LIBVDWXC_VERSION}*

# --- ELPA (scalable dense eigensolver; GPAW elpa=True) ----------------------
# CPU build (AVX2 + OpenMP, against our MPICH + OpenBLAS + ScaLAPACK): a
# better-scaling replacement for the ScaLAPACK dense diagonalisation. Headers
# install under <prefix>/include/elpa-<version>/; the siteconfig globs for it.
RUN set -eux; cd /tmp; \
    wget -q https://elpa.mpcdf.mpg.de/software/tarball-archive/Releases/${ELPA_VERSION}/elpa-${ELPA_VERSION}.tar.gz; \
    cp elpa-${ELPA_VERSION}.tar.gz ${SOURCES_DIR}/; \
    tar xzf elpa-${ELPA_VERSION}.tar.gz; cd elpa-${ELPA_VERSION}; \
    mkdir build && cd build; \
    ../configure \
        CC=mpicc CXX=mpicxx FC=mpifort \
        CFLAGS="-O3 -march=x86-64-v3 -ftree-vectorize -funsafe-math-optimizations -fno-math-errno" \
        FCFLAGS="-O3 -march=x86-64-v3 -ftree-vectorize -funsafe-math-optimizations -fno-math-errno" \
        SCALAPACK_LDFLAGS="-L${INSTALL_DIR}/scalapack/lib -Wl,-rpath,${INSTALL_DIR}/scalapack/lib -lscalapack -lopenblas" \
        SCALAPACK_FCFLAGS="-L${INSTALL_DIR}/scalapack/lib" \
        --prefix=${INSTALL_DIR}/elpa-${ELPA_VERSION} \
        --enable-openmp --disable-avx512 --disable-c-tests \
        --enable-runtime-threading-support-checks \
        --enable-allow-thread-limiting \
        --without-threading-support-check-during-build; \
    make -j "$(nproc)"; make install; \
    ln -sfn ${INSTALL_DIR}/elpa-${ELPA_VERSION} ${INSTALL_DIR}/elpa; \
    cd /; rm -rf /tmp/elpa-${ELPA_VERSION}*

# --- MAGMA (GPU dense linear algebra; GPAW magma=True, the GPU eigensolver) --
# CUDA build for Ampere (A40/A100) + Hopper (H200/GH200). Compiling GPU kernels
# for multiple arches is a long (~30-40 min) layer; it caches until the version
# bumps. MAGMA is GPU-only in GPAW (c/gpu/cpp/magma), so it pairs with the
# GPAW_BUILD_GPU=1 build below.
RUN set -eux; cd /tmp; \
    wget -q https://icl.utk.edu/projectsfiles/magma/downloads/magma-${MAGMA_VERSION}.tar.gz; \
    tar xzf magma-${MAGMA_VERSION}.tar.gz; \
    cmake -S magma-${MAGMA_VERSION} -B /tmp/magma-build \
        -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}/magma \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
        -DMAGMA_ENABLE_CUDA=ON -DGPU_TARGET="Ampere Hopper" \
        -DBLAS_LIBRARIES=/usr/lib/x86_64-linux-gnu/libopenblas.so \
        -DLAPACK_LIBRARIES=/usr/lib/x86_64-linux-gnu/libopenblas.so; \
    cmake --build /tmp/magma-build -j "$(nproc)"; \
    cmake --install /tmp/magma-build; \
    cd /; rm -rf /tmp/magma-build /tmp/magma-${MAGMA_VERSION}*

# --- GPU Python stack: torch 2.13.0 (fairchem pin) + cupy -------------------
RUN set -eux; \
    uv pip install torch==2.13.0 torchvision==0.28.0 \
        --index-url https://download.pytorch.org/whl/cu129; \
    uv pip install cupy-cuda12x==14.1.1

# --- curated Python stack (COPY late so a pin bump cache-busts here) ---------
COPY requirements-idrobolab.txt /opt/build/requirements-idrobolab.txt
RUN uv pip install -r /opt/build/requirements-idrobolab.txt

# --- dask-cuda for multi-GPU abTEM (deliberate --no-deps pairing) -----------
# The staged abTEM checkout already carries the multi-GPU code paths
# (ensure_cuda_cluster / is_gpu_dask_client); only the runtime was missing, so
# without this abTEM raises "The dask-cuda package is required to distribute
# computations across multiple GPUs" the moment dask.multi-gpu is enabled.
# See delta/verification/multigpu_abtem/README.md for the full analysis.
#
# --no-deps is NOT optional. dask-cuda 26.6.0 requires
# rapids-dask-dependency==26.6.*, which pins dask==2026.1.1 -- one of the exact
# releases abTEM excludes (pyproject: !=2025.12.*,!=2026.1.0,!=2026.1.1, for the
# to_zarr regression dask/dask#12205, fixed in 2026.1.2). Resolving normally
# would either fail outright or silently
# downgrade this image's dask into a state where abTEM computes correct results
# and then saves them wrongly. So install dask-cuda alone and add only its
# non-dask runtime deps: nvidia-ml-py, and cuda-core pinned <1.0 because the
# 1.x line drops the cuda.core.experimental namespace dask-cuda 26.6 imports.
# When RAPIDS >= 26.8 ships a dask-cuda built against dask 2026.7, this whole
# block collapses to a plain `pip install dask-cuda`.
#
# --no-deps means the rest of dask-cuda's requirements must already be here.
# Audited against its 26.6.0 metadata (checked 2026-08-18):
#   click>=8.1     <- dask (requires click>=8.1)
#   cuda-core      <- installed above
#   numpy          <- ase, torch
#   nvidia-ml-py   <- installed above
#   pandas>=1.3    <- pymatgen-core (pandas>=2) and hiphive
#   zict>=2.0.0    <- distributed (zict>=3.0.0)
#   rapids-dask-dependency==26.6.*  <- SKIPPED on purpose; it is the dask pin
# If any of those top-level packages ever leaves requirements-idrobolab.txt,
# re-check this list: the import test below catches a missing module, but a
# too-old one may only surface when a cluster is constructed on a GPU node.
#
# The torch guard is load-bearing: fairchem-core 2.22 pins torch~=2.13.0 and fixes
# this entire image (see requirements-idrobolab.txt). A dependency cascade that
# moved torch would be a silent, expensive regression, so fail the build loudly
# instead.
RUN set -eux; \
    torch_before="$(python -c 'import torch; print(torch.__version__)')"; \
    pip install nvidia-ml-py "cuda-core[cu12]>=0.3.2,<1.0"; \
    pip install --no-deps dask-cuda==26.6.0; \
    python -c "from dask_cuda import LocalCUDACluster; import cuda.core.experimental; print('dask-cuda import OK')"; \
    torch_after="$(python -c 'import torch; print(torch.__version__)')"; \
    if [ "$torch_before" != "$torch_after" ]; then \
        echo "ERROR: dask-cuda install moved torch $torch_before -> $torch_after;" >&2; \
        echo "       fairchem-core 2.22 pins torch~=2.13.0 -- refusing to build." >&2; \
        exit 1; \
    fi

# --- GPAW (editable; C ext built in-place, a copy stashed for bound clones) --
COPY siteconfig.py /opt/build/siteconfig.py
COPY src/gpaw /opt/src/gpaw
RUN set -eux; cd /opt/src/gpaw; \
    rm -rf build _gpaw*.so gpaw.egg-info; \
    pip install pybind11; \
    GPAW_BUILD_GPU=1 GPAW_CONFIG=/opt/build/siteconfig.py \
        pip install --no-build-isolation -v -e .; \
    cp _gpaw.*.so /opt/venv/lib/python3.12/site-packages/

# --- editable dev packages (bind a cluster checkout over /opt/src/<n>) -------
COPY src/gpaw-weaver /opt/src/gpaw-weaver
RUN pip install -e /opt/src/gpaw-weaver
COPY src/abTEM /opt/src/abTEM
RUN pip install -e /opt/src/abTEM

# --- LAMMPS (stable): GPU (CUDA sm_80) + KOKKOS (CUDA, AMPERE80) + 25 packages
# GPU package via CUDA and KOKKOS via CUDA (Kokkos_ARCH AMPERE80 — native
# A40/A100, PTX-JIT on Hopper). H5MD needs HDF5 (apt, serial); FFTW from
# /opt/software; kim-api auto-downloaded. ML-QUIP downloads and builds the
# libAtoms/QUIP library (Fortran + GAP, single-threaded; gfortran already
# present). LONG build (Kokkos-CUDA GPU kernels + GPU package + kim-api + QUIP +
# 25 packages). ML-IAP core only (no Python coupling; that needs cython). The
# python module is exposed via PYTHONPATH. PYTHONDONTWRITEBYTECODE keeps the
# build from scattering .pyc where cmake runs python for NumPy detection.
# The GPU package links the CUDA driver API (libcuda.so.1), absent in the
# GPU-less build sandbox: liblammps.so links against the toolkit's stub, but the
# lmp exe must then resolve that INDIRECT dep. Symlink the stub to the versioned
# name and point ld at it with -Wl,-rpath-link (-L/LIBRARY_PATH is NOT consulted
# for indirect deps); the real driver is injected at runtime (--nv).
#
# Build-time tests are opt-in: `--build-arg LAMMPS_RUN_TESTS=1` builds a SECOND,
# CPU-only LAMMPS (KOKKOS-OpenMP) with ENABLE_TESTING and runs the full ctest
# suite. A separate CPU build is required because the CUDA liblammps cannot be
# loaded in the GPU-less `docker build` sandbox (no driver libcuda.so.1). This
# verifies the CPU side of every package in the container's MPICH/FFTW/HDF5
# toolchain; the GPU-accelerated styles must be verified on a real GPU node.
# It roughly doubles the LAMMPS build time (a second QUIP build), so keep it 0
# for production images and set 1 only for verification builds.
# Pinned to a release tag, the one the devcontainer builds; the moving `stable` branch
# would change the release under an unchanged recipe. stable_30Sep2026 fails to link
# liblammps.so with the Kokkos-CUDA preset (g++: cannot specify '-o' with '-c' ... with
# multiple files), so do not move the pin without a CUDA build.
#
# LAMMPS (GPL-2.0), the QUIP checkout and the kim-api tarball its cmake fetches (QUIP: GPL-2.0
# with the GAP submodule under the non-commercial ASL; kim-api: CDDL-1.0) are kept in
# /opt/sources once the build has fetched them; the build fails when one is missing.
ARG LAMMPS_BRANCH=stable_22Jul2025_update6
ARG LAMMPS_RUN_TESTS=0
COPY keep-git-source.sh /tmp/keep-git-source.sh
RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends libhdf5-dev libzstd-dev ffmpeg; \
    rm -rf /var/lib/apt/lists/*; \
    export PYTHONDONTWRITEBYTECODE=1; \
    git clone --depth 1 -b "${LAMMPS_BRANCH}" https://github.com/lammps/lammps.git /tmp/lammps-src; \
    cd /tmp/lammps-src; \
    STUBS=/usr/local/cuda/lib64/stubs; \
    [ -e "$STUBS/libcuda.so" ] || STUBS="$(dirname "$(find /usr/local -name libcuda.so -path '*stubs*' 2>/dev/null | head -1)")"; \
    ln -sf "$STUBS/libcuda.so" "$STUBS/libcuda.so.1"; export LIBRARY_PATH="${LIBRARY_PATH:-}:$STUBS"; \
    PKGS="-D PKG_EXTRA-PAIR=on -D PKG_H5MD=on -D PKG_TALLY=on -D PKG_EXTRA-FIX=on \
        -D PKG_MISC=on -D PKG_SMTBQ=on -D PKG_REAXFF=on -D PKG_KIM=on -D DOWNLOAD_KIM=on \
        -D PKG_KSPACE=on -D PKG_MANYBODY=on -D PKG_ML-SNAP=on -D PKG_ML-IAP=on \
        -D PKG_ML-QUIP=on -D DOWNLOAD_QUIP=on -D PKG_MOLECULE=on \
        -D PKG_PYTHON=on -D PKG_INTERLAYER=on -D PKG_OPENMP=on -D PKG_QTB=on \
        -D PKG_OPT=on -D PKG_COMPRESS=on -D PKG_PLUGIN=on -D PKG_PHONON=on -D PKG_MEAM=on"; \
    cmake -S cmake -B build \
        -C cmake/presets/kokkos-cuda.cmake \
        -D CMAKE_INSTALL_PREFIX=${INSTALL_DIR}/lammps \
        -D CMAKE_BUILD_TYPE=Release \
        -D CMAKE_PREFIX_PATH=${INSTALL_DIR}/fftw \
        -D BUILD_MPI=on -D BUILD_OMP=on -D BUILD_SHARED_LIBS=on -D LAMMPS_EXCEPTIONS=on \
        -D Kokkos_ARCH_AMPERE80=on -D FFT=FFTW3 \
        -D PKG_GPU=on -D GPU_API=cuda -D GPU_ARCH=sm_80 \
        -D CMAKE_EXE_LINKER_FLAGS="-Wl,-rpath-link,$STUBS" \
        ${PKGS}; \
    cmake --build build -j"$(nproc)"; \
    cmake --install build; \
    QUIP_DIR=build/quip_build-prefix/src/quip_build; \
    bash /tmp/keep-git-source.sh . "lammps-${LAMMPS_BRANCH}"; \
    bash /tmp/keep-git-source.sh "$QUIP_DIR" "quip-$(git -C "$QUIP_DIR" rev-parse --short=12 HEAD)"; \
    cp build/kim_build-prefix/src/kim-api-*.txz ${SOURCES_DIR}/; \
    cp -a build/kim_build-prefix/lib/libkim-api.so* ${INSTALL_DIR}/lammps/lib/ 2>/dev/null || true; \
    mkdir -p ${INSTALL_DIR}/lammps/python; \
    cp -a python/lammps ${INSTALL_DIR}/lammps/python/lammps; \
    if [ "${LAMMPS_RUN_TESTS}" = "1" ]; then \
        cmake -S cmake -B build-test \
            -C cmake/presets/kokkos-openmp.cmake \
            -D CMAKE_BUILD_TYPE=Release -D CMAKE_PREFIX_PATH=${INSTALL_DIR}/fftw \
            -D BUILD_MPI=on -D BUILD_OMP=on -D BUILD_SHARED_LIBS=on -D LAMMPS_EXCEPTIONS=on \
            -D FFT=FFTW3 -D FFT_KOKKOS=FFTW3 -D ENABLE_TESTING=on ${PKGS}; \
        cmake --build build-test -j"$(nproc)"; \
        export LD_LIBRARY_PATH="/tmp/lammps-src/build-test:/tmp/lammps-src/build-test/kim_build-prefix/lib:${INSTALL_DIR}/fftw/lib:${LD_LIBRARY_PATH:-}"; \
        ctest --test-dir build-test -j4 --output-on-failure --timeout 600; \
    fi; \
    cd /; rm -rf /tmp/lammps-src
# (LAMMPS runtime env is set in the final stage below, not here.)

# ===== sources: the source code of the GPL, LGPL, MPL and CDDL software ========
# sources-collect checks that every component has its archive (the build fails otherwise)
# and writes SHA256SUMS. `sources` holds the archives and SHA256SUMS and nothing else;
# publish.sh builds it with --target sources and pushes it as <image>:<tag>-sources.
FROM builder AS sources-collect
COPY --from=qe-builder /opt/sources/ ${SOURCES_DIR}/
COPY finish-sources.sh /tmp/finish-sources.sh
RUN bash /tmp/finish-sources.sh qe lammps quip kim-api fftw libxc libvdwxc elpa bader

FROM scratch AS sources
LABEL org.opencontainers.image.source="https://github.com/IdroboLab/idrobolab-env"
LABEL org.opencontainers.image.description="Source code of the GPL, LGPL, MPL and CDDL software in the idrobolab image"
COPY --from=sources-collect /opt/sources/ /

# ============================================================================
# ===== idrobolab final image — slim runtime =================================
# -cudnn-runtime base + COPY --from=builder the artifacts + runtime libs only.
# GPAW's _gpaw.so, MAGMA and LAMMPS link the CUDA runtime libs in this base;
# torch/cupy bundle their own nvidia-* in the venv; libcuda.so.1 comes from --nv.
# ============================================================================
FROM nvcr.io/nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04

LABEL org.opencontainers.image.authors="IdroboLab (https://github.com/IdroboLab)"
LABEL org.opencontainers.image.source="https://github.com/IdroboLab/idrobolab-env"
LABEL purpose="idrobolab — DFT/multislice/ptychography/ML-potentials/EM-analysis"

ENV INSTALL_DIR=/opt/software \
    VIRTUAL_ENV=/opt/venv \
    MPLCONFIGDIR=/tmp/matplotlib
ENV PATH=/opt/venv/bin:/opt/software/mpich/bin:/opt/software/lammps/bin:/opt/software/qe/bin:/usr/local/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/software/mpich/lib:/opt/software/libxc/lib:/opt/software/libvdwxc/lib:/opt/software/fftw/lib:/opt/software/scalapack/lib:/opt/software/elpa/lib:/opt/software/magma/lib:/opt/software/lammps/lib \
    PYTHONPATH=/opt/software/lammps/python

# Runtime shared libs. Includes a Qt/X11/GL runtime
# group for nionswift/ptyrad (QT_QPA_PLATFORM=xcb). Best-effort noble names; the
# sanity + ldd gate below fail the build and name any missing .so.
# libpython3.12t64 is the SHARED libpython, which liblammps.so needs because
# LAMMPS is built with PKG_PYTHON=on. It is a separate package on noble: the
# python3.12 interpreter does not link libpython, so the interpreter runs fine
# without it and only the ldd closure catches the gap.
# gcc, g++, libc6-dev and python3.12-dev (the Python.h headers) are the one exception to
# "runtime only": orb-models' torch.compile / Triton / nvalchemi-toolkit-ops paths compile
# C and C++ extensions at run time and need gcc and g++ on PATH plus the Python headers.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv ca-certificates git \
        gcc g++ libc6-dev python3.12-dev \
        libpython3.12t64 \
        libgfortran5 libquadmath0 libgomp1 \
        libopenblas0-pthread \
        libhwloc15 libevent-2.1-7 libfabric1 \
        libssl3 libcurl4t64 \
        libhdf5-103-1t64 libzstd1 ffmpeg \
        libgl1 libglib2.0-0 libx11-6 libxcb1 libxkbcommon0 libdbus-1-3 fontconfig; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

# --- built artifacts from the builder stage ---------------------------------
COPY --from=builder /opt/software /opt/software
COPY --from=builder /opt/venv     /opt/venv
COPY --from=builder /opt/src      /opt/src
COPY --from=builder /usr/local/bin/bader /usr/local/bin/bader
COPY --from=qe-builder /opt/qe-dist ${INSTALL_DIR}/qe

COPY NVIDIA-NOTICE.txt SOURCES.txt nvidia-license-scan.py /opt/idrobolab/
COPY --from=sources-collect /opt/sources/SHA256SUMS /opt/idrobolab/sources/SHA256SUMS

COPY lammps-gpu-selftest.sh /usr/local/bin/lammps-gpu-selftest
RUN chmod +x /usr/local/bin/lammps-gpu-selftest

# --- build-time sanity: the slim image must still import the full stack ------
# pymatgen 2026.x is an umbrella namespace dist (Requires-Dist: pymatgen-core)
# with no pymatgen/__init__.py, so it has no __version__ and a bare
# `import pymatgen` would succeed on an empty namespace dir. Import
# pymatgen.core (the dist that carries Structure/Lattice) and read the version
# from the installed metadata instead.
RUN python -c "import numpy,scipy,ase,gpaw,_gpaw,pymatgen.core,phonopy,hiphive,abtem,torch; \
from importlib.metadata import version; \
assert hasattr(_gpaw,'new_blacs_context'),'GPAW built without ScaLAPACK'; \
assert hasattr(_gpaw,'FFTWPlan'),'GPAW built without FFTW'; \
print('gpaw',gpaw.__version__,'| torch',torch.__version__,'| ase',ase.__version__,'| pymatgen',version('pymatgen'))" \
 && command -v cc && command -v c++ && test -f "$(python -c 'import sysconfig;print(sysconfig.get_paths()["include"])')/Python.h" \
 && python -c "import fairchem.core, orb_models, ptyrad; print('ML/ptycho stack ok')" \
 && python -c "from dask_cuda import LocalCUDACluster; import dask, distributed; \
print('dask-cuda ok | dask',dask.__version__,'| distributed',distributed.__version__)" \
 && python -c "import nion.data; print('nionswift (headless data) ok')" \
 && mpichversion | head -1

# --- NVIDIA wheel licenses, printed to the build log ------------------------
RUN python /opt/idrobolab/nvidia-license-scan.py

# --- runtime lib-closure gate for the CUDA binaries (libcuda.so.1 excepted) --
# Checks every binary before failing, so one build names ALL the gaps rather
# than only the first — each rebuild here is expensive.
RUN set -eu; rc=0; for so in /opt/software/lammps/lib/liblammps.so /opt/software/qe/bin/pw.x; do \
      [ -e "$so" ] || { echo "missing artifact $so"; rc=1; continue; }; \
      miss="$(ldd "$so" 2>/dev/null | awk '/not found/ && !/libcuda/{print $1}')"; \
      if [ -n "$miss" ]; then echo "UNRESOLVED runtime libs for $so:"; echo "$miss"; rc=1; \
      else echo "$so: runtime libs resolved (libcuda.so.1 expected at --nv runtime)"; fi; \
    done; exit $rc

# --- the tag of this image's sources image (set by publish.sh) ---------------
# Declared last, so a new value rebuilds only this layer.
ARG SOURCES_TAG=
RUN if [ -n "${SOURCES_TAG}" ]; then \
      printf '\nThe sources image of this image: ghcr.io/idrobolab/idrobolab:%s\n' "${SOURCES_TAG}" \
        >> /opt/idrobolab/SOURCES.txt; \
    fi

# --- version identity (set by publish.sh) -----------------------------------
# manifest.json comes from prepare_build_context.sh; the build adds whether LAMMPS's ctest suite
# ran. The labels repeat the manifest's version, recipe hash and build id, which the registry
# shows without pulling the image. Declared last, like SOURCES_TAG.
ARG VERSION=
ARG RECIPE_HASH=
ARG BUILD_ID=
ARG LAMMPS_RUN_TESTS=0
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${RECIPE_HASH}" \
      idrobolab.build-id="${BUILD_ID}"
COPY src/manifest.json /opt/idrobolab/manifest.json
RUN python -c 'import json, sys; p = "/opt/idrobolab/manifest.json"; m = json.load(open(p)); \
m["lammps_ctest"] = sys.argv[1] == "1"; json.dump(m, open(p, "w"), indent=2)' "${LAMMPS_RUN_TESTS}" \
 && pip freeze > /opt/idrobolab/pip-freeze.txt

# --- runtime environment ----------------------------------------------------
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    QT_QPA_PLATFORM=xcb
CMD ["python"]
