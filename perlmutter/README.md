# Perlmutter (NERSC)

Environment setup for NERSC's Perlmutter HPC system (x86_64, AMD Milan;
NVIDIA A100 GPUs; Slingshot-11 interconnect; Slurm + Cray MPICH; containers
via podman-hpc, OCI/Docker images only).

## Contents

| Path | Purpose |
|---|---|
| [docs/](docs/) | **Start here as a new group member** — step-by-step introduction: account and `sshproxy` login (Windows/macOS/Linux), shell and group setup, storage and data transfer, jobs and queues, Python with uv, the idrobolab container, Jupyter, ThinLinc and Nion Swift |
| [../shared/containers/x86_64-cuda/otherimage/](../shared/containers/x86_64-cuda/otherimage/) | The container recipe (shared with Delta) — build & publish in its README |
| [podman-hpc.md](podman-hpc.md) | Perlmutter run notes: `podman-hpc pull`/`run`, MPI, GPU |
| [jupyter.md](jupyter.md) | Notebooks: jupyter.nersc.gov via a registered kernel, or your own allocation + `ssh -L`. Knobs, gotchas, troubleshooting |
| [verification/multigpu_abtem/](verification/multigpu_abtem/) | abTEM multi-GPU verification + HAADF scaling benchmark (launchers; payloads in `shared/`) |
| [jobs/](jobs/) | Slurm templates per node type and QOS (CPU 1/N-node, GPU shared/full-node/hbm80g/multi-node, debug, interactive) + node specs, QOS limits, charging |
| [jobs/interactive_jupyter.sh](jobs/interactive_jupyter.sh) | JupyterLab in the container on a compute node; prints the `ssh -L` tunnel line with the node name filled in |
| [helpers/setup-user.sh](helpers/setup-user.sh) | Per-user setup ([docs/02](docs/02-shell-setup.md)) — one command sets up your shell, Jupyter kernels, and checks what silently breaks later |
| [helpers/](helpers/) | Scripts run by hand on a login node: image pulls, store permissions, shared uv, the Nion Swift launcher |
| [helpers/update-image.sh](helpers/update-image.sh) | Pull/refresh an image into the shared CFS store (`/global/cfs/cdirs/<project>/podman-hpc`). Login nodes only |
| [nersc-filesystem-guard.md](nersc-filesystem-guard.md) | NERSC's hook that checks every Bash command an AI agent runs for broad filesystem scans: what it blocks, harmless `grep -r` regexes it blocks too, and how to write those |
| [claude-machine.md](claude-machine.md) | Claude Code's machine rules for sessions on a Perlmutter login node; linked as `~/.claude-machine.md` |
| [env.sh](env.sh) | Source from `~/.bashrc`: `PODMANHPC_ADDITIONAL_STORES` and friends, plus interactive aliases (`cds` `cdp` `q` `sr` `sp`). Silent, idempotent, inert off Perlmutter |

## Conventions

- Built container images, exported tarballs, build logs, and staged source
  trees (`src/`) are **not** tracked — only the recipes that reproduce them.
- Record the image digest (`podman-hpc images --digests`) alongside any
  campaign results for provenance.
