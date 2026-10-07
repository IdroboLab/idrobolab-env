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
| [delta/get-image.sh](../../delta/get-image.sh) | Materialize the Delta `.sif` from the published registry image (from a login node it queues itself on `cpu-interactive`; needs `ACCOUNT=<project>-delta-cpu`) |
| [delta/jobs/](../../delta/jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper); its README has the partition matrix and the MPI launch guide |
| [delta/verification/](../../delta/verification/) | On-node checks: [multi-GPU abTEM](../../delta/verification/multigpu_abtem/README.md) (launchers; the Python payloads are shared with Perlmutter in [`shared/verification/multigpu_abtem/`](../../shared/verification/multigpu_abtem/)) |
| [delta/AGENTS.md](../../delta/AGENTS.md) | Conventions for Delta, read by coding agents (`delta/CLAUDE.md` imports it) |

## Getting started

1. Run `accounts` on a Delta login node to find your charge accounts: `<project>-delta-cpu` for the CPU partitions, `<project>-delta-gpu` for the GPU partitions, charged separately.
2. Build the image once: `ACCOUNT=<project>-delta-cpu delta/get-image.sh` converts the registry image to a `.sif` on a compute node (the conversion is too heavy for a login node). Keep `.sif` files in `$PROJECTS_BASE/software/containers/`, not in scratch, and record `sha256sum` of the image with your results.
3. Copy the job template for your partition from [`delta/jobs/`](../../delta/jobs/), replace `<project>` in its `--account` line, and submit it with your script as the argument: `sbatch gpu_a100_1gpu.sbatch my_script.py`. Always set `--time`: the default is 30 minutes.
4. Run the smoke tests of the [first-run checklist](../../delta/jobs/README.md#first-run-checklist) once before the first real job.

## The images

The templates default to the `otherimage` image (`ghcr.io/<username>/otherimage`: GPAW with `gpaw.<module>`, another image, gpaw-weaver, PySlice and abTEM on CUDA 12.8 and MPICH 4.3.2). Its recipe is another image's recipe (maintained separately, not in this repo). The group's own image has its recipe in [`shared/containers/x86_64-cuda/idrobolab/`](../../shared/containers/x86_64-cuda/idrobolab/); the templates take any image through `SIF=/path/to/image.sif`. One image serves A40, A100 and H200 nodes: the GPU code is in fat multi-architecture wheels.

## Conventions

- Built container images (`*.sif`), build logs and staged source trees (`src/`) are **not** tracked, only the recipes that reproduce them.
- Source checkouts that override the image's editable packages are project-scoped (`<project-dir>/code/<name>` on `/projects`, bound over `/opt/src/<name>`); job output and other regenerable bulk goes to `$SCRATCH_BASE/$USER/...`. Details and the reasons are in [`delta/AGENTS.md`](../../delta/AGENTS.md).
- Delta jobs are charged to an allocation: 1 SU is one core-hour or one GPU-hour, `-interactive` queues cost twice their batch partition, `-preempt` half. The charge factors per partition are in the [partition matrix](../../delta/jobs/README.md#script--partition-matrix).
