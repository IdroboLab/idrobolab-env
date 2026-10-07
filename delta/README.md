# Delta (NCSA)

Files for NCSA's Delta HPC system (x86_64; NVIDIA A40/A100/H200 GPUs; Slurm + Cray MPICH;
containers via Apptainer).

## Contents

| Path | Purpose |
|---|---|
| [../docs/delta/](../docs/delta/README.md) | **Start here:** how to work on Delta: accounts, getting the image, submitting jobs, conventions |
| [AGENTS.md](AGENTS.md) | Conventions and traps for Delta, read by coding agents (`CLAUDE.md` imports it) |
| [get-image.sh](get-image.sh) | Materialize the Delta `.sif` from the published registry image (from a login node it queues itself on `cpu-interactive`; needs `ACCOUNT=<project>-delta-cpu`) |
| [jobs/](jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper); its README has the partition matrix and the MPI launch guide |
| [verification/multigpu_abtem/](verification/multigpu_abtem/) | abTEM multi-GPU verification + HAADF scaling benchmark (launchers; payloads in [`../shared/verification/multigpu_abtem/`](../shared/verification/multigpu_abtem/)) |

## Conventions

- Built container images (`*.sif`), build logs and staged source trees (`src/`) are
  **not** tracked, only the recipes that reproduce them.
- Record the image checksum (`sha256sum <image>.sif`) alongside any campaign results for
  provenance.
