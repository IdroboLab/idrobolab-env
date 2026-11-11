# Delta (NCSA)

Files for NCSA's Delta HPC system (x86_64; NVIDIA A40/A100/H200 GPUs; Slurm + Cray MPICH;
containers via Apptainer).

## Contents

| Path | Purpose |
|---|---|
| [../docs/delta/](../docs/delta/README.md) | **Start here:** how to work on Delta: accounts, getting the image, submitting jobs, conventions |
| [AGENTS.md](AGENTS.md) | Conventions and traps for Delta, read by coding agents (`CLAUDE.md` imports it) |
| [env.sh](env.sh) | Source from `~/.bashrc`, below `export DELTA_PROJECT=<project>`: sets `SCRATCH_BASE` and `PROJECTS_BASE`, keeps the Apptainer cache on personal scratch (`$SCRATCH_BASE/$USER`) and points uv at the project's shared cache (`$SCRATCH_BASE/uv-cache`) once an admin has created it, and puts the project's shared bin directory (`$PROJECTS_BASE/software/bin`, where uv is installed) on `PATH`. Silent, idempotent, inert while `DELTA_PROJECT` is unset |
| [helpers/setup-user.sh](helpers/setup-user.sh) | Per-user setup: writes the `~/.bashrc` block that exports `DELTA_PROJECT` and sources `env.sh`, creates the Apptainer cache directory, reports what is missing (`--check`, `--undo`) |
| [get-image.sh](get-image.sh) | Materialize the Delta `.sif` from the published registry image (from a login node it queues itself on `cpu-interactive`; needs `ACCOUNT=<project>-delta-cpu`) |
| [jobs/](jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper); its README has the partition matrix and the MPI launch guide |
| [verification/multigpu_abtem/](verification/multigpu_abtem/) | abTEM multi-GPU verification + HAADF scaling benchmark (launchers; payloads in [`../shared/verification/multigpu_abtem/`](../shared/verification/multigpu_abtem/)) |
