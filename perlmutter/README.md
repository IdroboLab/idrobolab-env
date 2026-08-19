# Perlmutter (NERSC)

Environment setup for NERSC's Perlmutter HPC system (x86_64, AMD Milan;
NVIDIA A100 GPUs; Slingshot-11 interconnect; Slurm + Cray MPICH; containers
via podman-hpc, OCI/Docker images only).

## Contents

| Path | Purpose |
|---|---|
| [../shared/containers/otherimage/](../shared/containers/otherimage/) | The container recipe (shared with Delta) — build & publish in its README |
| [podman-hpc.md](podman-hpc.md) | Perlmutter run notes: `podman-hpc pull`/`run`, MPI, GPU |
| [verification/multigpu_abtem/](verification/multigpu_abtem/) | abTEM multi-GPU verification + HAADF scaling benchmark (launchers; payloads in `shared/`) |
| [jobs/](jobs/) | Slurm templates per node type and QOS (CPU 1/N-node, GPU shared/full-node/hbm80g/multi-node, debug, interactive) + node specs, QOS limits, charging |
| [fix-store-perms.sh](fix-store-perms.sh) | Make the shared CFS store group-readable and verify it; `--check` reports only (cron-safe). Called by `update-image.sh` after every pull |
| [update-image.sh](update-image.sh) | Pull/refresh an image into the shared CFS store (`/global/cfs/cdirs/<project>/podman-hpc`). Login nodes only |
| [env.sh](env.sh) | Source from `~/.bashrc`: `PODMANHPC_ADDITIONAL_STORES` and friends. Silent, idempotent, inert off Perlmutter |

## Conventions

- Built container images, exported tarballs, build logs, and staged source
  trees (`src/`) are **not** tracked — only the recipes that reproduce them.
- Record the image digest (`podman-hpc images --digests`) alongside any
  campaign results for provenance.
