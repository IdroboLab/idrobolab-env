# GPAW siteconfig for the idrobolab container (x86_64, CPU C-extension):
# Mirrors the dev-machine build, with MPICH instead of OpenMPI (Delta's MPI;
# MPICH ABI allows host-MPI swap-in): MPICH + OpenBLAS + ScaLAPACK +
# FFTW(-MPI/OMP) + libxc 7.0.0 + libvdwxc 0.5.0, all under /opt/software.
#
# -march=x86-64-v3 (AVX2) is portable across Delta's AMD Milan CPUs and the
# login nodes; do not use -march=native inside a container build.
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

# Optional: GPAW's own CUDA kernels (NOT required for torch/jax/cupy GPU use;
# the dev environment runs GPAW on CPU). Covers A100 (sm_80), A40 (sm_86),
# H200 (sm_90). Enable with GPAW_BUILD_GPU=1 in the .def file if wanted.
if os.getenv('GPAW_BUILD_GPU', '0') == '1':
    gpu = True
    gpu_target = 'cuda'
    gpu_compiler = 'nvcc'
    gpu_include_dirs = []
    gpu_library_dirs = ['/usr/local/cuda/lib64']
    gpu_compile_args = [
        '-O3',
        '-gencode', 'arch=compute_80,code=sm_80',
        '-gencode', 'arch=compute_86,code=sm_86',
        '-gencode', 'arch=compute_90,code=sm_90',
    ]
    libraries += ['cudart', 'cublas']
