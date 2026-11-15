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

The [README](../README.md#license) gives the same split with the copyright holders.

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
  are named); `no`; or `unclear` (the item is also an entry under Open questions).

| Path | What | Source | License | Redistribution |
|---|---|---|---|---|
| `perlmutter/agents/nersc/LICENSE`, `claude/.claude/CLAUDE.md`, `codex/.codex/AGENTS.md` | NERSC's baseline instructions for coding agents on Perlmutter, copied byte for byte by `perlmutter/agents/sync-nersc.sh` | <https://github.com/NERSC/coding-agents>, commit recorded in `perlmutter/agents/nersc/UPSTREAM` | BSD 3-Clause, copyright NERSC (the file `perlmutter/agents/nersc/LICENSE`) | yes, with conditions: keep NERSC's copyright notice and license text with the files (they are there), and do not use NERSC's name to endorse the repository |
| `core/` (all files except `core/docs/LICENSE`) | Shared shell helpers, checks, tests, workflow templates and the LAMMPS GPU self-test, copied by `core/sync/sync-core.sh` | hpcenv-core, the repository linked in `README.md`; commit in `core/CORE_COMMIT` | BSD 3-Clause, copyright held by the person named in `core/LICENSE` | yes, with conditions: keep `core/LICENSE` with the files. The owner granted the rights; the differing copyright line is under Open questions (1) |
| `.github/workflows/core-drift.yml`, `core-sync.yml`, `personal-data.yml` | Copies of the workflow templates in `core/sync/workflows/`, made once and since the repository's own | hpcenv-core, as above | BSD 3-Clause, as `core/` | yes, with conditions: as `core/` |
| `docs/LICENSE`, `assets/LICENSE` (second part), `core/docs/LICENSE` | The legal text of the Creative Commons Attribution 4.0 International license, unaltered | <https://creativecommons.org/licenses/by/4.0/legalcode> | The text is dedicated to the public domain under CC0 (stated at the end of each file) | yes |
| `assets/idrobolab-folder.png`, `assets/idrobolab-uploads.ico` | The IdroboLab logo, and the same logo with a cloud added, as the ThinLinc folder icon and the upload tool's icon | The group; `assets/LICENSE` | CC BY 4.0, copyright IdroboLab | yes, with conditions: attribution as given in `assets/LICENSE`. The chain of rights to the artwork is under Open questions (2) |
| `perlmutter/verification/multigpu_abtem/abtem_bench_haadf_auto_<jobid>.out` (lines 9 to 21) | Job log of a group run; it contains the copyright and license notice that NVIDIA's CUDA container prints at start | NVIDIA CUDA container banner; the license named in it is the NVIDIA Deep Learning Container License | The notice is a statement printed by the container; the log is not a copy of the container or of the license | yes: only the printed notice is reproduced, unaltered |
| `docs/perlmutter/README.md` (acknowledgement quotation under "Acknowledging NERSC") | The wording NERSC asks users to put in publications | <https://www.nersc.gov/users/become-a-nersc-user/acknowledgement> | None found; NERSC publishes the wording for users to copy | yes: reuse is the purpose of the text |
| `shared/containers/x86_64-cuda/idrobolab/Dockerfile`, `siteconfig.py` | Container recipe and GPAW build configuration; the `Dockerfile` header says it is a sibling of another image's recipe and reuses its compiled foundation (MPICH, FFTW, ScaLAPACK, libxc, libvdwxc, GPAW) | The another image container recipe, maintained outside this repository | Not recorded in this repository | unclear: Open questions (3) |
| `perlmutter/agents/skills/delta-cluster/SKILL.md`, `docs/delta/README.md`, `delta/jobs/README.md` | Delta facts the group measured or read in NCSA's documentation: a partition and charge-factor table, the file-system label table, and a few quoted phrases | NCSA's Delta documentation, <https://docs.ncsa.illinois.edu/systems/delta/> (the page `running_jobs.html` and the Data Management page are named in the text) | None found | unclear: Open questions (4) |
| `docs/perlmutter/` pages (for example `04-jobs.md`, `reference/nersc-filesystem-guard.md`, `reference/podman-hpc.md`) | Descriptions of NERSC services and of NERSC's filesystem-guard hook (short quoted phrases, one checksum), with links to NERSC's pages | <https://docs.nersc.gov/> and the hook file named in `reference/nersc-filesystem-guard.md` | Not confirmed for the documentation; none found for the hook file | unclear: Open questions (5) |

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

## Open questions

Each entry is a question for the maintainer. None has an answer yet, and the items stay
`unclear` or conditional until it is answered.

1. **Copyright holders.** `README.md`, `LICENSE` and `docs/README.md` name the University of
   Washington as the holder of the scripts and documentation. `assets/LICENSE` names
   IdroboLab. `core/LICENSE` names a private person, and the files in `core/` came into this
   repository from the person's own repository. Does the University (or any other
   employer or funder of the authors of the history that moved here from the `hpcenvs`
   repository) have to approve a public release under BSD 3-Clause and CC BY 4.0? Should the
   holder line stay as it is?
2. **The logo.** Who drew the logo, and did the author license or assign it to IdroboLab?
   Can IdroboLab, as a group, hold the copyright the file says it holds? Is the cloud in
   `assets/idrobolab-uploads.ico` the group's own drawing or taken from a stock source?
   Should the logo carry a notice that CC BY 4.0 licenses the image but does not grant use
   of the IdroboLab name as a mark?
3. **another image's recipe.** The `Dockerfile` header says the recipe reuses the compiled
   foundation of another image's recipe. Under which license is that recipe, who holds its
   rights, and which files here (`Dockerfile`, `siteconfig.py`, others) were taken from it?
4. **NCSA documentation.** The `delta-cluster` skill and the Delta pages reproduce a
   partition table, a file-system label table and a few quoted phrases from NCSA's
   documentation. No license for it was found. Keep them, paraphrase them further, or ask
   NCSA?
5. **NERSC documentation and hook.** No license was confirmed for the text on
   `docs.nersc.gov`, and none was found for the filesystem-guard hook that
   `reference/nersc-filesystem-guard.md` describes with short quotations and a checksum.
   Is the level of quotation acceptable?
6. **The container image (outside this tree).** `install-qe-gpu.sh` copies runtime
   libraries of the NVIDIA HPC SDK into the final image, and the image is built on
   NVIDIA's CUDA and cuDNN images. The package `ghcr.io/idrobolab/idrobolab` is already
   public (an anonymous client can list its tags). Do NVIDIA's redistribution terms for
   those libraries and layers allow a public image?
7. **The group's own unpublished work.** The log file `abtem_bench_haadf_auto_<jobid>.out`
   is a benchmark result of the group, and job-template comments quote measured timings
   (for example in `perlmutter/jobs/ptyrad_4gpu_node.sbatch`). Are they cleared for
   publication?
