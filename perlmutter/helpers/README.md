# Perlmutter helpers

Scripts you run **by hand on a login node**, as opposed to the Slurm templates
in [`../jobs/`](../jobs/) (submitted with `sbatch`) and the campaign launchers
in [`../verification/`](../verification/).

| Script | Purpose | How often |
|---|---|---|
| [update-image.sh](update-image.sh) | Pull/refresh an image into the shared CFS store and fix its permissions. Login nodes only — compute nodes cannot write the store | Whenever a new image is published |
| [fix-store-perms.sh](fix-store-perms.sh) | Make the shared CFS store group-readable and verify it; `--check` reports only, exit 1 if broken (cron-safe) | Called by `update-image.sh` after every pull; by hand after a direct `podman-hpc pull --squash-dir` |
| [install-uv.sh](install-uv.sh) | Install or update `uv` in the shared project bin dir with group-correct permissions | Once, then to update uv — **instead of `uv self update`**, which cuts the rest of the project off |
| [install-jupyter-kernel.sh](install-jupyter-kernel.sh) | Register a Jupyter kernel — container, venv or conda env — so **jupyter.nersc.gov** runs your environment. `--shared` installs project-wide, `--link` adopts those per user; `--list` / `--remove` manage them | Once per environment; `--link` once per user |
| [setup-nionswift-launcher.sh](setup-nionswift-launcher.sh) | One-shot setup of the Nion Swift one-click launcher; detects whether it is on Perlmutter or a ThinLinc host | Once per maintainer, once per group member (ThinLinc side) — see [../nionswift-perlmutter-thinlinc.md](../nionswift-perlmutter-thinlinc.md) |

All are idempotent: re-running one is the normal way to update
(`install-jupyter-kernel.sh` wants `--force` to replace an existing kernel).

Two ways to reach a notebook, and they are complements rather than rivals:
`install-jupyter-kernel.sh` puts your environment in **jupyter.nersc.gov** —
no tunnel, nothing to keep open, survives a dropped laptop connection;
[`../jobs/interactive_jupyter.sh`](../jobs/interactive_jupyter.sh) gives you a
session on a node you allocated yourself, running the exact image the batch
jobs use. Both are documented in [../jupyter.md](../jupyter.md).

`update-image.sh` locates `fix-store-perms.sh` relative to its own file, so the
two must stay in this directory together. Everything else here is standalone.

Not in this directory, deliberately:

- [`../env.sh`](../env.sh) — sourced from `~/.bashrc`, not executed. It stays at
  `perlmutter/env.sh` so the source line people already have keeps working.
- `../jobs/interactive_gpu.sh`, `../jobs/interactive_jupyter.sh` — helpers
  rather than `sbatch` templates, but they share the mount/image/QOS
  conventions of the templates they sit beside, and `jobs/README.md`
  documents them in the same matrix.
