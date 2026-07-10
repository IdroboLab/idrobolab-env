# hpcenv_delta

Environment setup for NCSA's Delta HPC system (x86_64, AMD Milan; NVIDIA
A40/A100/H100 GPUs; Slingshot interconnect; Slurm + MPICH; containers via
Apptainer).

## Contents

| Path | Purpose |
|---|---|
| [containers/otherimage/](containers/otherimage/) | Apptainer build context for another image's GPAW software stack (see its README for build & run instructions) |

## Conventions

- Built container images (`*.sif`), build logs, and staged source trees
  (`src/`) are **not** tracked — only the recipes that reproduce them.
- Container images are built on the dev machine (or Delta) from these
  recipes; record the image checksum (`sha256sum <image>.sif`) alongside
  any campaign results for provenance.
