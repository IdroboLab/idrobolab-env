# Delta (NCSA)

How to work on NCSA's Delta HPC system (x86_64; AMD Milan CPUs, with Intel Xeon on the
H200 nodes; NVIDIA A40/A100/H200 GPUs; Slingshot 11 interconnect; Slurm + Cray MPICH;
containers via Apptainer). The files for Delta are in [`delta/`](../../delta/); this page
is the overview, [`delta/jobs/README.md`](../../delta/jobs/README.md) holds the partition
matrix, the MPI launch guide and the first-run checklist, and
[`delta/AGENTS.md`](../../delta/AGENTS.md) the conventions and traps that cost time on
Delta (environment variables, where files live, the editable-install import trap).

## Where things are

| Path | Purpose |
|---|---|
| [delta/env.sh](../../delta/env.sh) | Shell setup, sourced from `~/.bashrc`: Apptainer and uv caches on personal scratch |
| [delta/get-image.sh](../../delta/get-image.sh) | Materialize the Delta `.sif` from the published registry image (from a login node it queues itself on `cpu-interactive`; needs `ACCOUNT=<project>-delta-cpu`) |
| [delta/jobs/](../../delta/jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper); its README has the partition matrix and the MPI launch guide |
| [delta/verification/](../../delta/verification/) | On-node checks: [multi-GPU abTEM](../../delta/verification/multigpu_abtem/README.md) (launchers; the Python payloads are shared with Perlmutter in [`shared/verification/multigpu_abtem/`](../../shared/verification/multigpu_abtem/)) |
| [delta/AGENTS.md](../../delta/AGENTS.md) | Conventions for Delta, read by coding agents (`delta/CLAUDE.md` imports it) |

## Getting started

1. Run `accounts` on a Delta login node to find your charge accounts: `<project>-delta-cpu` for the CPU partitions, `<project>-delta-gpu` for the GPU partitions, charged separately.
2. Clone this repository to `~/idrobolab-env` on Delta, as described in [general page 2](../02-cloning.md).
3. Add this line to `~/.bashrc` on Delta, then log in again. It sources [`delta/env.sh`](../../delta/env.sh), which keeps the Apptainer and uv caches on your scratch (`$SCRATCH_BASE/$USER`) instead of your home quota:
   ```bash
   [ -r "$HOME/idrobolab-env/delta/env.sh" ] && . "$HOME/idrobolab-env/delta/env.sh"
   ```
   `IDROBOLAB_ENV_VERBOSE=1 . ~/idrobolab-env/delta/env.sh` prints what it set; if it reports `SCRATCH_BASE` as unset, the caches stay at their defaults in your home directory.
4. Build the image once, on a login node (it queues the conversion on a compute node itself, because the conversion is too heavy for a login node):
   ```bash
   mkdir -p $PROJECTS_BASE/software/containers && ACCOUNT=<project>-delta-cpu SIF=$PROJECTS_BASE/software/containers/idrobolab.sif ~/idrobolab-env/delta/get-image.sh
   ```
   The `.sif` lands in `$PROJECTS_BASE/software/containers/`, where the job templates look for it, not in scratch. Record `sha256sum` of the image with your results. The script pulls the group image `ghcr.io/idrobolab/idrobolab` by default; if it stops with `unauthorized`, ask an admin (see [The images](#the-images)).
5. Copy the job template for your partition from [`delta/jobs/`](../../delta/jobs/), replace `<project>` in its `--account` line, and submit it with your script as the argument: `sbatch gpu_a100_1gpu.sbatch my_script.py`. Always set `--time`: the default is 30 minutes.
6. Run the smoke tests of the [first-run checklist](../../delta/jobs/README.md#first-run-checklist) once before the first real job.

## The images

The templates default to the group's `idrobolab` image (`ghcr.io/idrobolab/idrobolab`): GPAW, abTEM and gpaw-weaver, with ptyrad, nionswift, fairchem, orb-models and phonopy, on CUDA 12.8 and Python 3.12. Its recipe is in [`shared/containers/x86_64-cuda/idrobolab/`](../../shared/containers/x86_64-cuda/idrobolab/), and its package is public, so `delta/get-image.sh` needs no credentials; if it fails with `unauthorized`, ask an admin. **The idrobolab image has not been run on Delta yet**: work through the [first-run checklist](../../delta/jobs/README.md#first-run-checklist) before a real job. The templates take any other image through `SIF=/path/to/image.sif`. One image serves A40, A100 and H200 nodes: the Python GPU wheels (torch, cupy) and MAGMA cover Ampere and Hopper, while the QE GPU build targets sm_80 and LAMMPS is built for AMPERE80, relying on PTX JIT on H200.

## Conventions

- Built container images (`*.sif`), build logs and staged source trees (`src/`) are **not** tracked, only the recipes that reproduce them.
- Source checkouts that override the image's editable packages are project-scoped (`<project-dir>/code/<name>` on `/projects`, bound over `/opt/src/<name>`); job output and other regenerable bulk goes to `$SCRATCH_BASE/$USER/...`. Details and the reasons are in [`delta/AGENTS.md`](../../delta/AGENTS.md).
- Delta jobs are charged to an allocation: 1 SU is one core-hour or one GPU-hour, `-interactive` queues cost twice their batch partition, `-preempt` half. The charge factors per partition are in the [partition matrix](../../delta/jobs/README.md#script--partition-matrix).
