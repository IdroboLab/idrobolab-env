# Perlmutter (NERSC)

Environment setup for NERSC's Perlmutter HPC system (x86_64, AMD Milan;
NVIDIA A100 GPUs; Slingshot-11 interconnect; Slurm + Cray MPICH; containers
via podman-hpc, OCI/Docker images only).

## Contents

| Path | Purpose |
|---|---|
| [../docs/perlmutter/](../docs/perlmutter/) | **Start here as a new group member** (after the general pages in [../docs/](../docs/)) — step-by-step introduction: account and `sshproxy` login (Windows/macOS/Linux), shell and group setup, storage and data transfer, jobs and queues, Python with uv, the idrobolab container, abTEM on 1–4 GPUs, Jupyter, ThinLinc and Nion Swift, coding agents, group conventions |
| [../shared/containers/x86_64-cuda/idrobolab/](../shared/containers/x86_64-cuda/idrobolab/) | The idrobolab container recipe — build & publish in its README |
| [podman-hpc.md](../docs/perlmutter/reference/podman-hpc.md) | Perlmutter run notes: `podman-hpc pull`/`run`, MPI, GPU |
| [jupyter.md](../docs/perlmutter/reference/jupyter.md) | Notebooks: jupyter.nersc.gov via a registered kernel, or your own allocation + `ssh -L`. Knobs, gotchas, troubleshooting |
| [verification/multigpu_abtem/](verification/multigpu_abtem/) | abTEM multi-GPU verification (launcher; payload in `shared/`) |
| [jobs/](jobs/) | Slurm templates per node type and QOS (CPU 1/N-node, GPU shared 1-2 GPUs/full-node/hbm80g/multi-node, abTEM from a uv environment, debug, interactive) + node specs, QOS limits, charging, testing status |
| [jobs/interactive_gpu_shared.sh](jobs/interactive_gpu_shared.sh) | Container shell on 1 or 2 GPUs of a shared node (`shared_interactive`, ≤ 4 h); `interactive_gpu.sh` is the whole-node twin |
| [examples/abtem/](examples/abtem/) | `abtem_gpu_example.py`: a small abTEM HAADF-type scan on a GPU or CPU, run by the uv job templates ([page 7](../docs/perlmutter/07-abtem.md)) |
| [jobs/interactive_jupyter.sh](jobs/interactive_jupyter.sh) | JupyterLab in the container on a compute node; prints the `ssh -L` tunnel line with the node name filled in |
| [agents/](agents/) | What members' coding agents follow: `group.md` (the group's rules), `skills/` (the group's agent skills: `perlmutter-cluster`, `idrobolab-container`), `nersc/` (a vendored copy of NERSC's baseline, with `UPSTREAM` naming the commit) and `sync-nersc.sh` (refreshes `nersc/`; run weekly by the `nersc-agents-sync` workflow). Installed by `helpers/setup-agents.sh` ([page 10](../docs/perlmutter/10-coding-agents.md#instructions-three-layers)) |
| [helpers/setup-user.sh](helpers/setup-user.sh) | Per-user setup ([page 2](../docs/perlmutter/02-shell-setup.md)) — one command sets up your shell, Jupyter kernels, and checks what silently breaks later |
| [helpers/](helpers/) | Scripts run by hand on a login node: image pulls, store permissions, shared uv, the Nion Swift launcher |
| [helpers/update-image.sh](helpers/update-image.sh) | Pull/refresh an image into the shared CFS store (`/global/cfs/cdirs/<project>/podman-hpc`). Login nodes only |
| [nersc-filesystem-guard.md](../docs/perlmutter/reference/nersc-filesystem-guard.md) | NERSC's hook that checks every Bash command an AI agent runs for broad filesystem scans: what it blocks, harmless `grep -r` regexes it blocks too, and how to write those |
| [env.sh](env.sh) | Source from `~/.bashrc`: `PODMANHPC_ADDITIONAL_STORES` and friends, plus interactive aliases (`cds` `cdp` `q` `sr` `sp`) and `sbatch`/`salloc` functions that add `-A "$NERSC_PROJECT"`. Silent, idempotent, inert off Perlmutter |

## Conventions

- Built container images, exported tarballs, build logs, and staged source
  trees (`src/`) are **not** tracked — only the recipes that reproduce them.
- Record the image digest (`podman-hpc images --digests`) alongside any
  campaign results for provenance.
