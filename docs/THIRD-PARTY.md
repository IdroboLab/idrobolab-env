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

## Open questions

- GPL software in the image (Quantum ESPRESSO, GPAW) is linked against proprietary CUDA
  libraries. This was not examined; the maintainers decide whether it needs a further step.
- The licenses of the Open MPI, UCX and HPC-X libraries bundled with the SDK are to be kept
  in the image. This is open until the first build log shows which `comm_libs` files are
  staged.
