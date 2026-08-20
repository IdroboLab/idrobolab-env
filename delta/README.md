# Delta (NCSA)

Environment setup for NCSA's Delta HPC system (x86_64; AMD Milan CPUs, with
Intel Xeon on the H200 nodes; NVIDIA A40/A100/H200 GPUs; Slingshot 11
interconnect; Slurm + Cray MPICH; containers via Apptainer).

## Contents

| Path | Purpose |
|---|---|
| [../shared/containers/x86_64-cuda/otherimage/](../shared/containers/x86_64-cuda/otherimage/) | The container recipe (shared with Perlmutter) — build & publish instructions in its README |
| [get-image.sh](get-image.sh) | Materialize the Delta `.sif` from the published registry image |
| [jobs/](jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper) — see its README for the partition matrix and MPI launch guide |
| [verification/](verification/) | On-node checks (e.g. multi-GPU abTEM) |

## Conventions

- Built container images (`*.sif`), build logs, and staged source trees
  (`src/`) are **not** tracked — only the recipes that reproduce them.
- Container images are built on the dev machine (or Delta) from these
  recipes; record the image checksum (`sha256sum <image>.sif`) alongside
  any campaign results for provenance.
