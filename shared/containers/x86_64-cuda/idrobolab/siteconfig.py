# GPAW siteconfig for the idrobolab container (x86_64, CPU C-extension):
# Mirrors the dev-machine build, with MPICH instead of OpenMPI (Delta's MPI;
# MPICH ABI allows host-MPI swap-in): MPICH + OpenBLAS + ScaLAPACK +
# FFTW(-MPI/OMP) + libxc 7.0.0 + libvdwxc 0.5.0, all under /opt/software.
#
# -march=x86-64-v3 (AVX2) is portable across Delta's AMD Milan CPUs and the
# login nodes; do not use -march=native inside a container build.
import glob
import os

mpi = True
compiler = 'mpicc'

for flag in ['-fopenmp', '-O3', '-march=x86-64-v3']:
    if flag not in extra_compile_args:
        extra_compile_args += [flag]

if '-fopenmp' not in extra_link_args:
    extra_link_args += ['-fopenmp']

prefixes = [
    '/opt/software/libxc',
    '/opt/software/libvdwxc',
    '/opt/software/fftw',
    '/opt/software/scalapack',
]

for prefix in prefixes:
    inc = os.path.join(prefix, 'include')
    lib = os.path.join(prefix, 'lib')
    if os.path.isdir(inc) and inc not in include_dirs:
        include_dirs += [inc]
    if os.path.isdir(lib):
        if lib not in library_dirs:
            library_dirs += [lib]
        if lib not in runtime_library_dirs:
            runtime_library_dirs += [lib]

# ScaLAPACK / BLACS
scalapack = True
if 'scalapack' not in libraries:
    libraries += ['scalapack']

# BLAS/LAPACK (Ubuntu OpenBLAS)
if 'openblas' not in libraries:
    libraries += ['openblas']

# libxc
libxc = True
if 'xc' not in libraries:
    libraries += ['xc']

# libvdwxc
libvdwxc = True
if 'vdwxc' not in libraries:
    libraries += ['vdwxc']

# FFTW (serial + OpenMP + MPI variants, built against our MPICH)
fftw = True
for name in ['fftw3_omp', 'fftw3_mpi', 'fftw3']:
    if name not in libraries:
        libraries += [name]

# ELPA (scalable dense eigensolver; alternative to the ScaLAPACK dense
# diagonalisation). Headers install in a versioned subdir, so glob for it —
# the ELPA version can bump in the Dockerfile without editing this file.
_elpa_root = '/opt/software/elpa'
_elpa_inc = glob.glob(os.path.join(_elpa_root, 'include', 'elpa-*'))
if _elpa_inc:
    elpa = True
    if 'elpa' not in libraries:
        libraries += ['elpa']
    _elpa_lib = os.path.join(_elpa_root, 'lib')
    if _elpa_lib not in library_dirs:
        library_dirs += [_elpa_lib]
    if _elpa_lib not in runtime_library_dirs:
        runtime_library_dirs += [_elpa_lib]
    if _elpa_inc[0] not in include_dirs:
        include_dirs += [_elpa_inc[0]]

# GPAW's own CUDA kernels: A100 (sm_80), A40 (sm_86), H200/GH200 (sm_90).
# Enabled at build time via GPAW_BUILD_GPU=1 (set in the Dockerfile).
# GPU use stays opt-in at runtime (GPAW_NEW=1 GPAW_USE_GPUS=1,
# parallel={'gpu': True}); a GPU-enabled build still runs CPU/MPI workflows
# unchanged. (torch/jax/cupy GPU use does NOT need this — it is for GPAW's
# own DFT kernels.)
if os.getenv('GPAW_BUILD_GPU', '0') == '1':
    gpu = True
    gpu_target = 'cuda'
    gpu_compiler = 'nvcc'
    cuda_home = os.getenv('CUDA_HOME', '/usr/local/cuda')
    cuda_inc = os.path.join(cuda_home, 'include')
    cuda_lib = os.path.join(cuda_home, 'lib64')
    gpu_include_dirs = [cuda_inc]
    gpu_library_dirs = [cuda_lib]
    gpu_compile_args = [
        '-O3',
        '-gencode', 'arch=compute_80,code=sm_80',
        '-gencode', 'arch=compute_86,code=sm_86',
        '-gencode', 'arch=compute_90,code=sm_90',
    ]
    libraries += ['cudart', 'cublas']
    # The host C compiler (mpicc) also pulls in <cuda.h> / <cuda_runtime_api.h>
    # / <cublas_v2.h> from the GPU-enabled C sources (c/operators.c,
    # c/transformers.c via gpu-runtime.h) and links the CUDA runtime, so the
    # cuda include/lib dirs must be on the *general* paths too, not only
    # gpu_include_dirs/gpu_library_dirs (which apply to nvcc only).
    if cuda_inc not in include_dirs:
        include_dirs += [cuda_inc]
    if cuda_lib not in library_dirs:
        library_dirs += [cuda_lib]
    if cuda_lib not in runtime_library_dirs:
        runtime_library_dirs += [cuda_lib]

    # MAGMA (GPU dense linear algebra for GPAW's GPU eigensolver). GPU-only in
    # GPAW (c/gpu/cpp/magma is compiled only when magma=True), so it lives
    # inside the GPU block; enable only when the library is actually present.
    if os.path.isdir('/opt/software/magma'):
        magma = True
        if 'magma' not in libraries:
            libraries += ['magma']
        _magma_lib = '/opt/software/magma/lib'
        _magma_inc = '/opt/software/magma/include'
        # nvcc compiles c/gpu/cpp/magma/*.cpp (which includes magma_v2.h), so
        # the magma include+lib must be on the GPU compiler's own paths
        # (gpu_include_dirs/gpu_library_dirs); the general include_dirs/
        # library_dirs are NOT passed to the GPU compile step.
        if _magma_inc not in gpu_include_dirs:
            gpu_include_dirs += [_magma_inc]
        if _magma_lib not in gpu_library_dirs:
            gpu_library_dirs += [_magma_lib]
        if _magma_lib not in library_dirs:
            library_dirs += [_magma_lib]
        if _magma_lib not in runtime_library_dirs:
            runtime_library_dirs += [_magma_lib]
        if _magma_inc not in include_dirs:
            include_dirs += [_magma_inc]
