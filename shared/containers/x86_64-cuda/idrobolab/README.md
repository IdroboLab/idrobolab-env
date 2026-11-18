# idrobolab container

Computational-materials + electron-microscopy-analysis environment: **GPAW**
(DFT), **abTEM** (multislice), **ptyrad** (ptychography), **nionswift** (EM data
analysis), ML interatomic potentials (**fairchem**, **orb-models**), phonons
(**phonopy**, **hiphive**), **pymatgen**, **dask**, **jupyterlab** — on CUDA
12.9 / Python 3.12 / x86_64.

One image serves Delta (Apptainer) and Perlmutter (podman-hpc).

## The one hard constraint: torch 2.13

`fairchem-core` (2.22) pins **`torch~=2.13.0`**, so this image uses **torch 2.13.0**
(with torchvision 0.28.0). At torch 2.13.x, `orb-models`
(≥2.8,<3) and `ptyrad` (≥2.4) are all satisfied, and `ase` is pinned `≥3.26` to
satisfy fairchem + orb-models + pymatgen simultaneously. fairchem v2 dropped
`torch-geometric`, so there is **no** `data.pyg.org` companion-wheel step. A
different torch minor means a different fairchem release.

## Contents

| File | Purpose |
|---|---|
| `Dockerfile` | The recipe (base: NGC `nvidia/cuda:12.9.1-cudnn-devel-ubuntu24.04`) |
| `requirements-idrobolab.txt` | Curated Python stack — **hand-maintained** (not scraped from a dev venv) |
| `siteconfig.py` | GPAW build config (MPICH/ScaLAPACK/FFTW/libxc/libvdwxc) |
| `prepare_build_context.sh` | Stages the three editable trees (gpaw, gpaw-weaver, abTEM) into `./src/`, committed files only (`git archive`), and `lammps-gpu-selftest.sh` from `core/lammps/` |
| `publish.sh` | Build + push to `ghcr.io/idrobolab/idrobolab`, then build the `sources` stage and push it as `<tag>-sources` and `<date>-sources` (see [Sources image](#sources-image)); refuses to build when the staged `lammps-gpu-selftest.sh` is missing or differs from `core/lammps/` |
| `install-qe-gpu.sh`, `stage-qe-libs.sh` | Build Quantum ESPRESSO in the NVIDIA HPC SDK image; `stage-qe-libs.sh` copies QE's runtime libraries and fails the build when a library from the SDK is not a `REDIST*` file or an NVIDIA CUDA/NCCL library comes from outside the SDK, copies SDK files unmodified and lists them in `NVIDIA-REDIST-FILES.txt`, and sets the rpath of the QE executables and of the non-SDK libraries |
| `NVIDIA-NOTICE.txt` | Names the NVIDIA agreements that govern the image's NVIDIA components and points to the file list; copied to `/opt/idrobolab/NVIDIA-NOTICE.txt` |
| `SOURCES.txt` | Names the GPL, LGPL, MPL and CDDL software in the image, where its source is (the sources image) and how to extract it, and where the recipe is; copied to `/opt/idrobolab/SOURCES.txt` |
| `keep-git-source.sh`, `finish-sources.sh` | Keep and check the source archives of the sources image (see [Sources image](#sources-image)) |
| `nvidia-license-scan.py` | Prints the license metadata and license files of each `nvidia-*` distribution in `/opt/venv`; run at build time (see the build log), copied to `/opt/idrobolab/` |
| `lammps-gpu-selftest.sh` | Not tracked: `prepare_build_context.sh` stages it from `core/lammps/` (the vendored hpcenv-core) for the Dockerfile's `COPY` |

### Multi-GPU abTEM (dask-cuda)

The staged abTEM checkout carries the multi-GPU code paths, so the image also
installs **dask-cuda 26.6.0** with `--no-deps`. Without it
`ensure_cuda_cluster()` raises *"The dask-cuda package is required to distribute
computations across multiple GPUs"* as soon as `dask.multi-gpu` is enabled —
loudly, not as a silent fall back to one GPU.

`--no-deps` is mandatory: dask-cuda 26.6.0 requires `rapids-dask-dependency`
`==26.6.*`, which pins `dask==2026.1.1` — one of the releases abTEM excludes for
the `to_zarr` regression. `requirements-idrobolab.txt` therefore also carries
abTEM's exclusion set so the resolve lands correctly the first time. The full
analysis, including the Plan B downgrade, is in
[`delta/verification/multigpu_abtem/README.md`](../../../../delta/verification/multigpu_abtem/README.md).
The Dockerfile block lists which package supplies each skipped dependency; the
build fails loudly if the install moves `torch` off the 2.13 version fairchem pins.

**Editable** installs from `/opt/src` (bind a cluster checkout over
`/opt/src/<name>` to run any branch): **gpaw** (vanilla
`master`; `GPAW_REF=<ref>` overrides), **gpaw-weaver** and **abTEM** (the commit
each dev checkout has checked out), all three staged from committed files by
`prepare_build_context.sh` (its header says why): commit a change, and `git add`
a new file, before building if it should be in the image. Everything else comes
from the pinned requirements. PAW datasets come from the `gpaw-data` pip
package.

## Build & run

```bash
# 1. stage (in the devcontainer):
./prepare_build_context.sh
# 2. build on a host with docker/podman (layer-cached), then push; needs GHCR_USER
#    (your GitHub username) and GITHUB_PACKAGE_TOKEN (a PAT with write:packages):
./publish.sh                              # -> ghcr.io/idrobolab/idrobolab
# 3. consume:
apptainer build idrobolab.sif docker://ghcr.io/idrobolab/idrobolab:latest   # Delta
podman-hpc pull ghcr.io/idrobolab/idrobolab:latest                          # Perlmutter
```

### Sources image

The licenses of some software in the image (Quantum ESPRESSO, LAMMPS, FFTW, libvdwxc, Bader,
QUIP, kim-api, ELPA, libxc; the audit is in
[`docs/THIRD-PARTY.md`](../../../../docs/THIRD-PARTY.md)) require its source code to be
available. The stages that download or clone it keep the archive in `/opt/sources`: a
downloaded tarball as it came, a git tree (with the submodules the build initialised, without
`.git`) as `<name>-<version>.tar.gz` through `keep-git-source.sh`. The stage `sources-collect`
runs `finish-sources.sh`, which fails the build when a listed component has no archive and
writes `SHA256SUMS`; the last stage before the image, `FROM scratch AS sources`, holds only
the archives and `SHA256SUMS`. Add a component to the list in `sources-collect` when it gets a
source duty.

The main image carries only `SHA256SUMS` (`/opt/idrobolab/sources/SHA256SUMS`) and
`/opt/idrobolab/SOURCES.txt`, not the archives. `publish.sh` builds the stage with
`--target sources` (cached from the build of the image) and pushes it right after the image
as `ghcr.io/idrobolab/idrobolab:<tag>-sources` and as
`ghcr.io/idrobolab/idrobolab:<date>-sources` (UTC date and time of the publish).

**Retention.** Never delete a sources image while its image is still available by tag or
digest, and never move or delete a `<date>-sources` tag: it is how the sources of an image
that `:latest` no longer points to stay available. To pull and check a sources image, use
the commands in `SOURCES.txt`.

### Registry access

`ghcr.io/idrobolab/idrobolab` is **public**, so `podman-hpc pull`
needs no credentials.

GHCR packages are private on first push, though, and stay that way until the
visibility is changed by hand — idrobolab was, until it was flipped. An
unauthenticated pull of a private package fails with

```
unable to retrieve auth token: invalid username/password: unauthorized
```

which reads like a credential problem but really means "not readable
anonymously": the client sent no credentials and GHCR refused to issue even
an anonymous token. If that reappears (a new package, or visibility reset),
either flip it public at
`github.com/orgs/IdroboLab/packages/container/idrobolab/settings`, or log in
on the cluster with a PAT carrying `read:packages`:

```bash
# Perlmutter (login node — pulled images are auto-squashed and visible to
# compute nodes, so no `podman-hpc migrate` is needed):
podman-hpc login ghcr.io -u <github-user>         # paste the PAT at the prompt

# Delta:
export APPTAINER_DOCKER_USERNAME=<github-user>
export APPTAINER_DOCKER_PASSWORD=$GITHUB_PACKAGE_TOKEN
apptainer build idrobolab.sif docker://ghcr.io/idrobolab/idrobolab:latest
```

Check whether the package exists and your PAT can read it, from anywhere. The
tags list is the real test: the token endpoint answers `200` either way (with
an `errors` array instead of a token when it refuses), and an unauthenticated
manifest request answers `401` even for a public package, so neither status
on its own tells you anything.

```bash
TOKEN=$(curl -s -u <github-user>:$GITHUB_PACKAGE_TOKEN \
    "https://ghcr.io/token?service=ghcr.io&scope=repository:idrobolab/idrobolab:pull" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/idrobolab/idrobolab/tags/list
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
# GAP/DFT MPI (single node, in-container): see Delta's job templates (delta/jobs/) for the
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

**Built and pulled on Perlmutter** (image `sha256:d0affd85…`, 20.4 GB, built
2026-08-18). The full stack resolves together and imports inside the real image:

```
dask 2026.7.1 | distributed 2026.7.1
torch 2.8.0+cu129 | abtem 1.1.0 | multi-GPU symbols present
```

Three things that were only reasoned about are now measured:

- The `--no-deps dask-cuda` pairing holds. `dask` is **2026.7.1**, not the
  `2026.1.1` that `rapids-dask-dependency` would have pinned — the release abTEM
  excludes for the `to_zarr` regression, which would have computed correct
  results and saved them wrongly.
- `torch` is still **2.8.0**, so the fairchem-core 2.21 ceiling survived the
  dask-cuda install. The build guard would have failed loudly otherwise.
- The image's own abTEM (1.1.0, editable from the staged `dev` checkout) already
  exposes `ensure_cuda_cluster` / `is_gpu_dask_client`. A branch checkout reports
  the **same version**, which is why the verification launchers discriminate on
  `abtem.__file__` and never on `__version__`.

Not yet exercised: the nionswift GUI path (needs a forwarded display), the
LAMMPS/QE GPU binaries, and multi-node GPU MPI.
