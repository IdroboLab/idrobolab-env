# another image / GPAW container for NERSC Perlmutter

OCI (Docker-format) build context reproducing the dev-machine Python
environment for Perlmutter's GPU nodes, consumed with **podman-hpc**
(NERSC's recommended container runtime; Apptainer SIF images are not
supported at NERSC).

This is the same recipe as the Apptainer definition proven for NCSA Delta
(`hpcenv_delta/containers/otherimage/`), translated to a Dockerfile: same
base image, same versions, same build steps. **Status: the Delta variant is
built and verified end-to-end (67/67 extra-module tests); this Dockerfile
translation has not been built yet** — the dev machine has no docker/podman.
First build attempt may need minor fixes.

## Fit to Perlmutter

- **CPU/GPU**: AMD Milan + A100 (sm_80) — covered by the `-march=x86-64-v3`
  CPU code and the fat cu129/cuda12 wheels (torch 2.13.0, jax 0.10.2, cupy).
- **MPI**: stock MPICH 4.3.2 built from source with shared libraries —
  exactly NERSC's documented recommendation, so `podman-hpc run --mpi` can
  swap in the ABI-compatible (`libmpi.so.12`), Slingshot-optimized Cray
  MPICH at runtime. Without `--mpi`, the container's own MPICH still works
  (TCP transport).

## Contents

| File | Purpose |
|---|---|
| `Dockerfile` | OCI image recipe (base: NGC `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`) |
| `requirements-perlmutter.txt` | All PyPI packages pinned to the dev-env versions — auto-generated, do not edit by hand |
| `siteconfig-perlmutter.py` | GPAW build configuration (MPI, ScaLAPACK, FFTW, libxc, libvdwxc) |
| `prepare_build_context.sh` | Regenerates `requirements-perlmutter.txt` from the live dev env, then stages the four source trees into `./src/` |

The four dev packages (**gpaw** a fork branch with an extra module,
**another image**, **gpaw-weaver**, **PySlice**) are installed **editable** at
`/opt/src/<name>`; mount a cluster checkout over that path to run any
branch. PAW datasets come from the `gpaw-data` pip package inside the image.

## Build

Stage the context on the dev machine, then build either on Perlmutter or on
any docker/podman host:

```bash
cd containers/otherimage
./prepare_build_context.sh        # regenerates pins + stages ./src

# Option A — on a Perlmutter login node (rsync this directory over first):
podman-hpc build -t otherimage:latest .
podman-hpc migrate otherimage:latest    # make it visible to compute nodes

# Option B — any docker/podman host, then via a registry:
docker build -t <registry>/<user>/otherimage:latest .
docker push <registry>/<user>/otherimage:latest
# ...and on Perlmutter:
podman-hpc pull <registry>/<user>/otherimage:latest
```

## Run on Perlmutter

```bash
# GPU, single node
podman-hpc run --rm --gpu otherimage:latest python script.py

# GPAW, MPI across nodes — --mpi injects the host Cray MPICH (MPICH ABI)
srun -N 4 --ntasks-per-node=64 \
    podman-hpc run --rm --mpi otherimage:latest python gpaw_script.py

# Hybrid MPI+OpenMP (OMP_NUM_THREADS defaults to 1 in the image)
srun -N 2 --ntasks-per-node=16 -c 8 \
    podman-hpc run --rm --mpi -e OMP_NUM_THREADS=8 \
    otherimage:latest python gpaw_script.py

# GPAW test suite (container fs is writable per-instance under podman)
podman-hpc run --rm otherimage:latest \
    bash -c 'cd /opt/src/gpaw && pytest gpaw/test/extra-module/'
```

Check the current NERSC podman-hpc docs for the exact `--mpi`/`--gpu` flag
names and srun integration — these follow NERSC's documented patterns but
may evolve.

## Running your own branches (cluster checkouts)

Same pattern as the Delta image — the dev packages resolve to
`/opt/src/<name>`, so mount a checkout over that path:

```bash
cd $SCRATCH/code
git clone git@gitlab.com:<username>/gpaw.git && git -C gpaw checkout <branch>

podman-hpc run --rm --gpu \
    -v $SCRATCH/code/gpaw:/opt/src/gpaw \
    otherimage:latest python script.py
```

Mount only the repos you want to override. Another image, gpaw-weaver, and
PySlice are pure Python — any branch just works. For **gpaw**, the compiled
`_gpaw.so` stashed in site-packages serves clones without one; if your
branch changes the C sources, rebuild in-place in the mounted clone with the
container's toolchain:

```bash
podman-hpc run --rm -v $SCRATCH/code/gpaw:/opt/src/gpaw otherimage:latest \
    bash -c 'cd /opt/src/gpaw && GPAW_CONFIG=/opt/build/siteconfig.py \
             python setup.py build_ext --inplace'
```

## Notes and caveats

- **torch cu129**: if `download.pytorch.org/whl/cu129` no longer carries the
  pinned version, switch the index to a CUDA variant that does (any 12.x
  variant covers sm_80).
- **nvalchemi-toolkit-ops** is installed best-effort; on failure the build
  continues and orb-models uses its pure-torch path.
- **PAW datasets**: `gpaw-data` is auto-discovered by GPAW 25.x; fallback
  `GPAW_SETUP_PATH=/opt/venv/lib/python3.12/site-packages/gpaw_data/setups`.
- Custom core-hole setups generated at runtime should live in a mounted
  host directory; add it to `gpaw.setup_paths` in the script as usual.
