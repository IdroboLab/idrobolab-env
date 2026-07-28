# ============================================================================
# idrobolab — computational-materials + microscopy-analysis container.
# GPAW (DFT) + abTEM (multislice) + ptyrad (ptychography) + nionswift (EM data)
# + ML potentials (fairchem, orb-models) + phonons (phonopy, hiphive) +
# pymatgen + dask + jupyterlab, on CUDA 12.8 / Python 3.12 / x86_64.
#
# Sibling of shared/containers/otherimage: it reuses the identical compiled
# foundation (MPICH/FFTW/ScaLAPACK/libxc/libvdwxc + GPAW) and swaps the Python
# stack. KEY DIFFERENCE: fairchem-core pins torch~=2.8, so this image uses
# torch 2.8.0 (NOT 2.13). fairchem v2 needs no torch-geometric wheels.
#
# Build (host with docker/podman, after ./prepare_build_context.sh):
#   podman build -t idrobolab:latest .        # or ./publish.sh to push to ghcr
#   -> apptainer build idrobolab.sif docker-daemon://idrobolab:latest   (Delta)
#   -> podman-hpc pull …                                                (Perlmutter)
#
# Layer-cached: compiled libs + GPU wheels are early; requirements + the three
# editable source trees are copied late so a pin/source change rebuilds only
# from there.
# ============================================================================
FROM nvcr.io/nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

LABEL org.opencontainers.image.authors="IdroboLab (https://github.com/IdroboLab)"
LABEL purpose="idrobolab — DFT/multislice/ptychography/ML-potentials/EM-analysis"

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ENV INSTALL_DIR=/opt/software \
    VIRTUAL_ENV=/opt/venv \
    PIP_NO_CACHE_DIR=1 \
    PIP_RETRIES=10 \
    PIP_TIMEOUT=120 \
    UV_HTTP_TIMEOUT=180 \
    UV_NO_CACHE=1
ENV PATH=/opt/venv/bin:/opt/software/mpich/bin:/usr/local/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/software/mpich/lib:/opt/software/libxc/lib:/opt/software/libvdwxc/lib:/opt/software/fftw/lib:/opt/software/scalapack/lib:/opt/software/elpa/lib:/opt/software/magma/lib

ARG MPICH_VERSION=4.3.2
ARG FFTW_VERSION=3.3.10
ARG SCALAPACK_VERSION=2.2.0
ARG LIBXC_VERSION=7.0.0
ARG LIBVDWXC_VERSION=0.5.0
ARG ELPA_VERSION=2024.05.001
ARG MAGMA_VERSION=2.7.2
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

# --- MPICH (ch4:ofi; MPICH ABI libmpi.so.12) --------------------------------
RUN set -eux; cd /tmp; \
    wget -q https://www.mpich.org/static/downloads/${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz; \
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

# --- GPU Python stack: torch 2.8.0 (fairchem ceiling) + cupy ----------------
RUN set -eux; \
    uv pip install torch==2.8.0 torchvision==0.23.0 \
        --index-url https://download.pytorch.org/whl/cu129; \
    uv pip install cupy-cuda12x==13.5.1

# --- curated Python stack (COPY late so a pin bump cache-busts here) ---------
COPY requirements-idrobolab.txt /opt/build/requirements-idrobolab.txt
RUN uv pip install -r /opt/build/requirements-idrobolab.txt

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
#
# Build-time tests are opt-in: `--build-arg LAMMPS_RUN_TESTS=1` builds a SECOND,
# CPU-only LAMMPS (KOKKOS-OpenMP) with ENABLE_TESTING and runs the full ctest
# suite. A separate CPU build is required because the CUDA liblammps cannot be
# loaded in the GPU-less `docker build` sandbox (no driver libcuda.so.1). This
# verifies the CPU side of every package in the container's MPICH/FFTW/HDF5
# toolchain; the GPU-accelerated styles must be verified on a real GPU node.
# It roughly doubles the LAMMPS build time (a second QUIP build), so keep it 0
# for production images and set 1 only for verification builds.
ARG LAMMPS_BRANCH=stable
ARG LAMMPS_RUN_TESTS=0
RUN set -eux; \
    apt-get update; apt-get install -y --no-install-recommends libhdf5-dev; \
    rm -rf /var/lib/apt/lists/*; \
    export PYTHONDONTWRITEBYTECODE=1; \
    git clone --depth 1 -b "${LAMMPS_BRANCH}" https://github.com/lammps/lammps.git /tmp/lammps-src; \
    cd /tmp/lammps-src; \
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
        ${PKGS}; \
    cmake --build build -j"$(nproc)"; \
    cmake --install build; \
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
ENV PATH=${INSTALL_DIR}/lammps/bin:${PATH} \
    LD_LIBRARY_PATH=${INSTALL_DIR}/lammps/lib:${LD_LIBRARY_PATH} \
    PYTHONPATH=${INSTALL_DIR}/lammps/python:${PYTHONPATH:-}

# Runtime GPU self-test (the GPU paths cannot be exercised at build time): run
# it inside the container ON A GPU NODE to verify the GPU package + KOKKOS-CUDA
# backends run and agree with CPU.
#   apptainer exec --nv idrobolab.sif lammps-gpu-selftest
COPY lammps-gpu-selftest.sh /usr/local/bin/lammps-gpu-selftest
RUN chmod +x /usr/local/bin/lammps-gpu-selftest

# --- build-time sanity (CPU-only; GPU checks need a real node) ---------------
RUN python -c "import numpy,scipy,ase,gpaw,_gpaw,pymatgen,phonopy,hiphive,abtem,torch; \
assert hasattr(_gpaw,'new_blacs_context'),'GPAW built without ScaLAPACK'; \
assert hasattr(_gpaw,'FFTWPlan'),'GPAW built without FFTW'; \
print('gpaw',gpaw.__version__,'| torch',torch.__version__,'| ase',ase.__version__,'| pymatgen',pymatgen.__version__)" \
 && python -c "import fairchem.core, orb_models, ptyrad; print('ML/ptycho stack ok')" \
 && python -c "import nion.data; print('nionswift (headless data) ok')" \
 && mpichversion | head -1

# --- runtime environment ----------------------------------------------------
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    QT_QPA_PLATFORM=xcb
CMD ["python"]
