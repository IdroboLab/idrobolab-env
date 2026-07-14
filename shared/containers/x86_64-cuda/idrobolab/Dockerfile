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
    LD_LIBRARY_PATH=/opt/software/mpich/lib:/opt/software/libxc/lib:/opt/software/libvdwxc/lib:/opt/software/fftw/lib:/opt/software/scalapack/lib

ARG MPICH_VERSION=4.3.2
ARG FFTW_VERSION=3.3.10
ARG SCALAPACK_VERSION=2.2.0
ARG LIBXC_VERSION=7.0.0
ARG LIBVDWXC_VERSION=0.5.0
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
    GPAW_CONFIG=/opt/build/siteconfig.py pip install --no-build-isolation -v -e .; \
    cp _gpaw.*.so /opt/venv/lib/python3.12/site-packages/

# --- editable dev packages (bind a cluster checkout over /opt/src/<n>) -------
COPY src/gpaw-weaver /opt/src/gpaw-weaver
RUN pip install -e /opt/src/gpaw-weaver
COPY src/abTEM /opt/src/abTEM
RUN pip install -e /opt/src/abTEM

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
