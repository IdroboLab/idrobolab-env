# Third-party material and rights

This page lists every item in the repository that was not written in the IdroboLab group,
where it comes from, under which license, and whether that license allows the item to stay
in this repository when the repository is public. It was made by reading every tracked
file, every `LICENSE` and `UPSTREAM` file, the headers and comments of the scripts, and the
links in the documentation. Items that only download third-party software when a user or
a build runs them (the `Dockerfile`, the install scripts, `setup-nionswift-launcher.sh`)
do not redistribute it and are not listed.

## The repository's own licenses

| What | License | Where |
|---|---|---|
| Scripts, job templates, container recipe, agent instructions and everything else outside the three rows below | BSD 3-Clause | [LICENSE](../LICENSE) |
| Documentation in `docs/` | CC BY 4.0 (commands and snippets in it also under BSD 3-Clause) | [docs/LICENSE](LICENSE) |
| Logo and icons in `assets/` | CC BY 4.0, copyright IdroboLab | [assets/LICENSE](../assets/LICENSE) |
| `perlmutter/agents/nersc/`, `core/` | their own licenses, see the table below | |

The [README](../README.md#license) gives the same split with the copyright holders. The
University of Washington stays the copyright holder named in `LICENSE`, `README.md` and
`docs/README.md`. In the maintainer's view, no approval by the University is needed for
the public release.

## How to read the table

Each row is one item or one group of files that belong together. The columns are:

- **Path**: where the item is in the repository.
- **What**: what the item is.
- **Source**: where it comes from (URL or upstream repository, and the version the
  repository holds where one is recorded).
- **License**: the license the source states. "None found" means no license was found at
  the source; it does not mean the item is free to use.
- **Redistribution**: whether that license allows the item to stay in a public repository
  that carries this repository's own licenses. `yes`; `yes, with conditions` (the conditions
  are named); `no`; or `kept` (no license was found, and the maintainer decided to keep
  the item as it is).

| Path | What | Source | License | Redistribution |
|---|---|---|---|---|
| `perlmutter/agents/nersc/LICENSE`, `claude/.claude/CLAUDE.md`, `codex/.codex/AGENTS.md` | NERSC's baseline instructions for coding agents on Perlmutter, copied byte for byte by `perlmutter/agents/sync-nersc.sh` | <https://github.com/NERSC/coding-agents>, commit recorded in `perlmutter/agents/nersc/UPSTREAM` | BSD 3-Clause, copyright NERSC (the file `perlmutter/agents/nersc/LICENSE`) | yes, with conditions: keep NERSC's copyright notice and license text with the files (they are there), and do not use NERSC's name to endorse the repository |
| `core/` (all files except `core/docs/LICENSE`) | Shared shell helpers, checks, tests, workflow templates and the LAMMPS GPU self-test, copied by `core/sync/sync-core.sh` | hpcenv-core, the repository linked in `README.md`; commit in `core/CORE_COMMIT` | BSD 3-Clause, copyright held by the person named in `core/LICENSE` | yes, with conditions: keep `core/LICENSE` with the files. The copyright holder named in `core/LICENSE` is this repository's maintainer, who licensed `core/` under BSD 3-Clause |
| `.github/workflows/core-drift.yml`, `core-sync.yml`, `personal-data.yml` | Copies of the workflow templates in `core/sync/workflows/`, made once and since the repository's own | hpcenv-core, as above | BSD 3-Clause, as `core/` | yes, with conditions: as `core/` |
| `docs/LICENSE`, `assets/LICENSE` (second part), `core/docs/LICENSE` | The legal text of the Creative Commons Attribution 4.0 International license, unaltered | <https://creativecommons.org/licenses/by/4.0/legalcode> | The text is dedicated to the public domain under CC0 (stated at the end of each file) | yes |
| `assets/idrobolab-folder.png`, `assets/idrobolab-uploads.ico` | The IdroboLab logo, and the same logo with a cloud added, as the ThinLinc folder icon and the upload tool's icon | The group; `assets/LICENSE` | CC BY 4.0, copyright IdroboLab | yes, with conditions: attribution as in `assets/LICENSE`; the group member who drew the logo and the cloud agreed to their release under CC BY 4.0 |
| `docs/perlmutter/README.md` (acknowledgement quotation under "Acknowledging NERSC") | The wording NERSC asks users to put in publications | <https://www.nersc.gov/users/become-a-nersc-user/acknowledgement> | None found; NERSC publishes the wording for users to copy | yes: reuse is the purpose of the text |
| `perlmutter/agents/skills/delta-cluster/SKILL.md`, `docs/delta/README.md`, `delta/jobs/README.md` | Delta facts the group measured or read in NCSA's documentation: a partition and charge-factor table, the file-system label table, and a few quoted phrases | NCSA's Delta documentation, <https://docs.ncsa.illinois.edu/systems/delta/> (the page `running_jobs.html` and the Data Management page are named in the text) | None found | kept: short factual tables and quotations with a link to the source (the maintainer's decision) |
| `docs/perlmutter/` pages (for example `04-jobs.md`, `reference/nersc-filesystem-guard.md`, `reference/podman-hpc.md`) | Descriptions of NERSC services and of NERSC's filesystem-guard hook (short quoted phrases, one checksum), with links to NERSC's pages | <https://docs.nersc.gov/> and the hook file named in `reference/nersc-filesystem-guard.md` | Not confirmed for the documentation; none found for the hook file | kept: the level of quotation is acceptable (the maintainer's decision) |

## Checked, with no row

- `setup-nionswift-launcher.sh` downloads the Nion Swift launcher icon into the member's
  own cache at run time and converts it for that member's desktop. No Nion file is
  committed.
- The `Dockerfile` and `install-qe-gpu.sh` fetch NVIDIA, MPICH, FFTW, ScaLAPACK, libxc,
  libvdwxc, ELPA, MAGMA, Bader, LAMMPS, GPAW and Quantum ESPRESSO sources at build time.
  The sources are not in the repository.
- Links to other sites (oh-my-bash, Globus, rclone, ThinLinc, Slurm, uv) are links only.
- Every other script, job template, document and agent skill carries no foreign copyright
  line, SPDX tag or "adapted from" note.

## Container image (outside this tree)

The recipe in `shared/containers/x86_64-cuda/idrobolab/` builds the public image
`ghcr.io/idrobolab/idrobolab`. The image is not part of this tree, but it carries NVIDIA
software, so its terms are recorded here. The findings below are a reading of NVIDIA's
license texts, not legal advice.

- **CUDA and cuDNN base layers.** The
  [NVIDIA Deep Learning Container License](https://developer.nvidia.com/ngc/nvidia-deep-learning-container-license)
  allows a derived container that includes the entire NVIDIA container and adds material
  functionality. The derived container must be distributed under terms at least as
  protective of NVIDIA's components as that license, the notices must be kept, NVIDIA's
  components must not be redistributed stand-alone, and the image must not claim NVIDIA's
  endorsement.
- **NVIDIA HPC SDK runtime libraries** copied into the image by `install-qe-gpu.sh`. The
  [HPC SDK license](https://docs.nvidia.com/hpc-sdk/eula/index.html) allows them to be
  redistributed only if they come from the SDK's REDIST directories and are bundled with,
  and used only by, the application that needs them (Quantum ESPRESSO); the image's users
  may not redistribute them further.
- **NVIDIA wheels from PyPI.** The license files of `nvidia-cublas-cu12`,
  `nvidia-cuda-runtime-cu12`, `nvidia-cufft-cu12` and `nvidia-cudnn-cu12` name the CUDA
  EULA or the cuDNN license, which allow redistribution with an application, unmodified
  and with the notices kept. The `License.txt` of `nvidia-nccl-cu12` is BSD 3-Clause, while
  its package metadata names `LicenseRef-NVIDIA-Proprietary`. The license files of the other
  NVIDIA wheels in the image were not read.

The repository's licenses cover the group's own files only; NVIDIA's components keep their
own terms. The image carries `/opt/idrobolab/NVIDIA-NOTICE.txt`, which names these
agreements. `stage-qe-libs.sh`, run by `install-qe-gpu.sh`, fails the build when a library
copied from the SDK is not a REDIST file (the real path of a file under a `REDIST*`
directory, or a byte-identical copy of one of the same name), and when a library with an
NVIDIA CUDA or NCCL name comes from outside the SDK. It lists the staged SDK files in
`/opt/software/qe/NVIDIA-REDIST-FILES.txt` and never modifies them. The build log lists the
license metadata and license files of each `nvidia-*` wheel (`nvidia-license-scan.py`).

## Open-source software in the image

The image compiles or downloads open-source software that is not NVIDIA's. Whoever
distributes GPL binaries must also provide their corresponding source, which is the source
the binaries were built from plus the scripts that control the build. The recipe is in this
repository; the source is in a second image, described below. These findings are a reading
of the licenses, not legal advice.

**The audit.** Each license below was read from the component's own source tree, at the
version the recipe fetches (the tarball or git tag it names; the Bader source from the
download page of its site). Rows: one component each. Columns: the version in the recipe;
the license the source states; the file read for it; and the duty it puts on the image
(**source**: the sources image holds the source; **notice**: the license text must go with
the binary). No patch is applied to any of these sources in the recipe. The one change to a
source tree is made by LAMMPS's own `ML-QUIP.cmake`: its `PATCH_COMMAND` copies a generated
`arch/Makefile.lammps` into the QUIP tree. That file is not in the QUIP archive, but it is
generated from the LAMMPS source, which is.

| Component | Version | License | File read | Duty |
|---|---|---|---|---|
| Quantum ESPRESSO | `qe-7.6` | GPL 2 or later | `README.md` (section LICENSE: "version 2 ... or (at your option) any later version"); `License` is the GPL 2 text | source. The submodules cmake initialises with the options of `install-qe-gpu.sh` are expected to be the next three rows (from the `qe-7.6` cmake files; only the first real build log confirms which are initialised, and the build's check covers whatever is); their source is in the same archive. d3q, pw2qmcpack, qe-gipaw (plugins off), fox (`QE_ENABLE_FOX` off) and lapack (internal LAPACK off) are expected not to be |
| Wannier90, a QE submodule | commit `1d6b187` | GPL 2 | `README.rst` ("licensed under GPLv2"), `LICENSE` (GPL 2 text) | source |
| libMBD, a QE submodule | commit `89a3cc1` | MPL 2.0 | `LICENSE`, `pyproject.toml` | source |
| DeviceXlib, a QE submodule | commit `a6b89ef` | GPL, version not stated | file headers of `src/deviceXlib_mod.f90` ("GNU General Public License. See the file `License'"); the tree has no license file | source |
| LAMMPS | `stable_22Jul2025_update6` | GPL 2 | `LICENSE` (GPL 2 text); `README` ("GNU Public License (GPL) version 2") | source |
| FFTW | 3.3.10 | GPL 2 or later | `COPYRIGHT` (file header), `COPYING` (GPL 2 text) | source |
| libvdwxc | 0.5.0 | GPL 3 or later | `LICENSE` (notice: "version 3 ... or (at your option) any later version"), `COPYING` (GPL 3 text) | source |
| Bader | 1.05 | GPL 3 or later; `jacobi_mod.f90` under the LGPL (its header says "GNU LGPL", no version), `dsyevj3_mod.f` under the LGPL 2.1 or later | `main.f90`, `jacobi_mod.f90` and `dsyevj3_mod.f` (file headers); neither the source nor the binary tarball has a license file | source (see below for the version match) |
| QUIP, as `ML-QUIP` downloads it (commit in LAMMPS's `cmake/Modules/Packages/ML-QUIP.cmake`) | `1e2f84ba94bc` | GPL 2, parts public domain; its GAP submodule under the GAP Academic Software License | `README.md` (QUIP has no license file at its top level); `src/GAP/LICENSE.md` | source. The submodules `GAP` (above) and `fox` (next row) are in the archive |
| FoX, a QUIP submodule | commit `5ad1c47` | BSD-style | `src/fox/LICENSE` | notice |
| kim-api | 2.2.1 | CDDL 1.0 | `LICENSE.CDDL` | source |
| ELPA | 2024.05.001 | LGPL 3 | `LICENSE` | source |
| libxc | 7.0.0 | MPL 2.0 | `COPYING` | source |
| MPICH | 4.3.2 | MPICH license (permissive, own text) | `COPYRIGHT` | notice |
| ScaLAPACK | 2.2.0 | modified BSD | `LICENSE` | notice |
| MAGMA | 2.7.2 | BSD | `COPYRIGHT` | notice |
| GPAW, abTEM | checkouts staged by `prepare_build_context.sh` | GPL 3 or later | `LICENSE` and `pyproject.toml` of each checkout | source: stays in the image at `/opt/src` |
| gpaw-weaver | same | MIT | `LICENSE`, `pyproject.toml` | notice |
| hyperspy, nionswift, gpaw-data | 2.5.0, 16.18.1, 1.0.1 | GPL 3 or later; GPL 3 only; GPL 3 or later | PyPI metadata of each release (not the source archive); each wheel is pure Python (`py3-none-any`) | source: the wheel is the source |
| ase, ptyrad | 3.29.0, 1.0.0 | LGPL 2.1 or later; LGPL 3 | PyPI metadata; pure-Python wheels | source: the wheel is the source |

The Python rows read the PyPI metadata on 2026-11-18. nionswift, gpaw-data and ptyrad are
pinned in `requirements-idrobolab.txt`, so their rows are the installed versions; hyperspy
and ase are not pinned, and their rows give the latest release.

**Bader: source and binary.** The recipe downloads the precompiled `bader_lnx_64.tar.gz`
from the Henkelman group's site, which also offers the Fortran source as `bader.tar.gz`.
Both state version 1.05 (08/19/23): the binary holds the string
`GRID BASED BADER ANALYSIS  (Version 1.05 08/19/23)`, which the source's `main.f90` prints,
and the site gives both files the same modification date. The build checks that the binary
and the downloaded source both carry `Version 1.05 ` and fails otherwise; the source is
kept as `bader-1.05.tar.gz`. The site's source link is not versioned, so the check is what
keeps a later release from being filed under 1.05. The download page names the binary as
built with ifort and the recipe does not rebuild it, so the match is by version, not by a
rebuild.

**The sources image.** The stages of the Dockerfile that download or clone the software
marked "source" keep its source archive, as the build fetched it, in `/opt/sources`:
`<name>-<version>.tar.gz` (git trees without `.git`, with the submodules the build
initialised), the kim-api tarball as downloaded, and Bader's. The Dockerfile's last
stage before the image, `FROM scratch AS sources`, collects them with a `SHA256SUMS`.
`publish.sh` builds it with `--target sources` from the same build and pushes it before the
image, so that no binary is out without its source: first
`ghcr.io/idrobolab/idrobolab:<date>-sources` (the UTC date and time the script started, never
moved), then the image, then `<tag>-sources` with the same `<tag>` as the image; when the
push of the image fails, `<tag>-sources` still matches the old `<tag>`. The build fails when a
component has no archive. The image itself holds `/opt/idrobolab/SOURCES.txt`, which names
the licenses, the command that extracts the sources image, the recipe and, on its last line,
the exact `<date>-sources` tag of the image's own sources image (`publish.sh` passes it to the
build), and `SHA256SUMS`, as `/opt/idrobolab/sources/SHA256SUMS`, which identifies the sources
image of an image built another way. A sources image is never
deleted while its image is available by tag or digest. GPLv2 counts "equivalent access to
copy the source code from the same place" as distributing the source, and the sources image
is in the same package as the image.

**CUDA libraries linked by GPL software.** Quantum ESPRESSO, LAMMPS and GPAW are linked
against NVIDIA's proprietary CUDA libraries. The maintainers decided on 2026-11-18 to
document this and take no further step, and not to ask the copyright holders. The basis:
the copyright holders themselves build and distribute CUDA versions (QE's GPU port is
developed with NVIDIA, and NVIDIA's NGC distributes a QE container), and the System Library
exception of GPLv3 fits the CUDA runtime better than that of GPLv2, which does not apply to
a library that "accompanies the executable", as the CUDA libraries do here.

**Ubuntu packages.** The packages of the base image and those installed with `apt` are
out of scope of the sources image. They are passed on unmodified, and their source code is in
the Ubuntu archive.

**GAP in LAMMPS.** The GAP part of QUIP is under the GAP Academic Software License, which
allows non-commercial use only and whose text says it is incompatible with the GPL. The image
builds LAMMPS with it (`HAVE_GAP=1`, `HAVE_DESCRIPTORS_NONCOMMERCIAL=1` in LAMMPS's
`ML-QUIP.cmake`), inside GPL-licensed `liblammps.so`. The maintainers keep it in the image
and accept that risk. `SOURCES.txt` in the image tells users that the GAP part is for
non-commercial use only.

## Open questions

- kim-api (CDDL 1.0) is linked into GPL-licensed `liblammps.so`. The maintainers decide
  whether it needs a step.
- PySide6 (6.12.0 on PyPI, under the LGPL 3, GPL 2 or GPL 3) comes from compiled wheels that
  bundle the Qt libraries; the sources image does not hold the source of Qt.
- The licenses of the other Python wheels in `/opt/venv`, those not named above, were not
  read. Whether the image carries the license texts that MPICH, ScaLAPACK and MAGMA require
  with binaries was not checked either; the MPICH built for Quantum ESPRESSO ships its
  `COPYRIGHT` as `/opt/software/qe/MPICH-COPYRIGHT`.
