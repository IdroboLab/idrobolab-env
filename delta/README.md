# hpcenv_delta

Environment setup for NCSA's Delta HPC system (x86_64; AMD Milan CPUs, with
Intel Xeon on the H200 nodes; NVIDIA A40/A100/H200 GPUs; Slingshot 11
interconnect; Slurm + Cray MPICH; containers via Apptainer).

## Contents

| Path | Purpose |
|---|---|
| [containers/otherimage/](containers/otherimage/) | Apptainer build context for another image's GPAW software stack (see its README for build & run instructions) |
| [jobs/](jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper) — see its README for the partition matrix and MPI launch guide |

## Conventions

- Built container images (`*.sif`), build logs, and staged source trees
  (`src/`) are **not** tracked — only the recipes that reproduce them.
- Container images are built on the dev machine (or Delta) from these
  recipes; record the image checksum (`sha256sum <image>.sif`) alongside
  any campaign results for provenance.
