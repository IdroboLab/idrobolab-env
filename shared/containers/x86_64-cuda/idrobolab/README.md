# idrobolab container

Computational-materials + electron-microscopy-analysis environment: **GPAW**
(DFT), **abTEM** (multislice), **ptyrad** (ptychography), **nionswift** (EM data
analysis), ML interatomic potentials (**fairchem**, **orb-models**), phonons
(**phonopy**, **hiphive**), **pymatgen**, **dask**, **jupyterlab** — on CUDA
12.8 / Python 3.12 / x86_64.

Sibling of [`../otherimage/`](../otherimage/): it reuses the **identical
compiled foundation** (MPICH + FFTW + ScaLAPACK + libxc + libvdwxc + GPAW) and
swaps the Python stack. Builds and distributes the same way (one image for
Delta via Apptainer and Perlmutter via podman-hpc).

## The one hard constraint: torch 2.8

`fairchem-core` (2.21) pins **`torch~=2.8`**, so this image uses **torch 2.8.0**,
not 2.13 like another image. At torch 2.8.x, `orb-models` (≥2.8,<3) and `ptyrad`
(≥2.4) are all satisfied, and `ase` is pinned `≥3.26` to satisfy fairchem +
orb-models + pymatgen simultaneously. fairchem v2 dropped `torch-geometric`, so
there is **no** `data.pyg.org` companion-wheel step. If you ever need torch
2.13, you must drop fairchem.

## Contents

| File | Purpose |
|---|---|
| `Dockerfile` | The recipe (base: NGC `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`) |
| `requirements-idrobolab.txt` | Curated Python stack — **hand-maintained** (not scraped from a dev venv) |
| `siteconfig.py` | GPAW build config (MPICH/ScaLAPACK/FFTW/libxc/libvdwxc) |
| `prepare_build_context.sh` | Stages the three editable trees (gpaw, gpaw-weaver, abTEM) into `./src/` |
| `publish.sh` | Build + push to `ghcr.io/<username>/idrobolab` |

**Editable** installs from `/opt/src` (bind a cluster checkout over
`/opt/src/<name>` to run any branch, as in another image): **gpaw** (<username> fork,
a branch), **gpaw-weaver**, **abTEM**. Everything else comes from the pinned
requirements. PAW datasets come from the `gpaw-data` pip package.

## Build & run

```bash
# 1. stage (in the devcontainer):
./prepare_build_context.sh
# 2. build on a host with docker/podman (layer-cached), then push:
./publish.sh                              # -> ghcr.io/<username>/idrobolab
# 3. consume:
apptainer build idrobolab.sif docker://ghcr.io/<username>/idrobolab:latest   # Delta
podman-hpc pull ghcr.io/<username>/idrobolab:latest                          # Perlmutter
```

### Registry access

GHCR packages are **private on first push** and stay that way until the
visibility is changed by hand. `ghcr.io/<username>/otherimage` is public;
`ghcr.io/<username>/idrobolab` is **not**, so an unauthenticated pull fails with

```
unable to retrieve auth token: invalid username/password: unauthorized
```

which reads like a credential problem but is really "this package is not
readable anonymously". Either flip the package to public at
`github.com/users/<username>/packages/container/idrobolab/settings`, or log in
on the cluster first with a PAT carrying `read:packages`:

```bash
# Perlmutter (login node — pulled images are auto-squashed and visible to
# compute nodes, so no `podman-hpc migrate` is needed):
podman-hpc login ghcr.io -u <username>          # paste the PAT at the prompt

# Delta:
export APPTAINER_DOCKER_USERNAME=<username>
export APPTAINER_DOCKER_PASSWORD=$GITHUB_PACKAGE_TOKEN
apptainer build idrobolab.sif docker://ghcr.io/<username>/idrobolab:latest
```

Check whether the package exists and your PAT can read it, from anywhere:

```bash
TOKEN=$(curl -s -u <username>:$GITHUB_PACKAGE_TOKEN \
    "https://ghcr.io/token?service=ghcr.io&scope=repository:<username>/idrobolab:pull" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/<username>/idrobolab/tags/list
```

podman-hpc stores the login under `$XDG_RUNTIME_DIR/containers/auth.json`,
which does not survive a logout; add
`--authfile $HOME/.config/containers/auth.json` to `login` and `pull` to keep
it. If the image needs to stay private long-term, NERSC's own Harbor registry
(`registry.nersc.gov`, project-scoped, request access via help.nersc.gov) is
the better home than a private GHCR package.

Common uses:
```bash
apptainer exec --nv idrobolab.sif python script.py        # GPU compute
apptainer exec --nv idrobolab.sif jupyter lab --no-browser --ip=0.0.0.0
# GAP/DFT MPI (single node, in-container): see ../otherimage jobs for the
# mpiexec -bootstrap fork / srun --mpi=pmi2 patterns (same MPICH).
```

### nionswift GUI

`nionswift` installs headlessly (the data model / `nion.data` imports without
Qt). The **GUI** needs a Qt backend (PySide6, included) plus a display:
```bash
apptainer exec --nv idrobolab.sif nionswift              # with a forwarded X display (ThinLinc/VNC)
apptainer exec idrobolab.sif xvfb-run -a nionswift       # headless (virtual display)
```
The image ships the Qt6 runtime libs + `xvfb`; `QT_QPA_PLATFORM=xcb` is set.

## Status

**Not yet built.** The recipe is assembled from PyPI metadata (July 2026) and
mirrors the proven another image foundation, but the idrobolab Python stack
(fairchem + ptyrad + nionswift + pymatgen + …) has not been resolved together
in a real build. Likely first-build adjustments: exact patch versions,
`nvalchemi-toolkit-ops` (pulled by orb-models) availability, and any Qt runtime
lib the nionswift GUI needs beyond the set installed here. Build on a host (the
devcontainer is unprivileged) and iterate with layer caching.
