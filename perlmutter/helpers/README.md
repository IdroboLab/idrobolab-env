# Perlmutter helpers

Scripts you run **by hand on a login node**, as opposed to the Slurm templates
in [`../jobs/`](../jobs/) (submitted with `sbatch`) and the campaign launchers
in [`../verification/`](../verification/).

| Script | Purpose | How often |
|---|---|---|
| [setup-user.sh](setup-user.sh) | Per-user setup: sources `env.sh` from your shell startup file, links the shared Jupyter kernels, checks group membership / image-store readability / `$SCRATCH`. `--check` reports only, `--undo` removes the block, `--vscode-workspace` also writes the VS Code workspace file; run it from your own clone | Once per user; re-run any time |
| [check-setup.sh](check-setup.sh) | Check your whole setup and report: this clone (behind/ahead of GitHub, local changes), `setup-user.sh --check` (which includes `setup-agents.sh --check`), whether `env.sh` is active with the current image name, and leftover paths to another clone or the old shared checkout ([page 2, section 6](../../docs/perlmutter/02-shell-setup.md#6-checking-your-setup)). Never prompts; writes only inside the clone's `.git`; exit 1 on a FAIL | After the setup, after a `git pull` or a move of your clone, when something behaves oddly |
| [setup-agents.sh](setup-agents.sh) | Make Claude Code and Codex follow NERSC's baseline and the group rules from `../agents/`, and link the group's skills (`../agents/skills/`) into their skills folders; `--check`, `--undo` ([page 10](../../docs/perlmutter/10-coding-agents.md#instructions-three-layers)) | Once per user; re-run after every `git pull` |
| [make-vscode-workspace.sh](make-vscode-workspace.sh) | Write `~/perlmutter.code-workspace`: your home directory, the project's CFS tree, any folders you name and `$SCRATCH` in one VS Code window, home first so the Claude Code extension shows the same sessions in every window; the big folders are not watched. `setup-user.sh --vscode-workspace` runs it with `--if-absent`; run it by hand to rewrite the file or to add folders ([page 11, section 4](../../docs/perlmutter/11-vscode.md#4-one-window-for-home-projects-and-scratch)) | Once, if you want the workspace (`setup-user.sh --vscode-workspace` does it); by hand to change the folders |
| [update-image.sh](update-image.sh) | Pull/refresh an image and fix its store's permissions: a released tag into the shared CFS store, `TAG=dev` and `TAG=<N>-rc` into your own `$SCRATCH/storage`. Login nodes only — compute nodes cannot reach the registry | Whenever a new image is published |
| [fix-store-perms.sh](fix-store-perms.sh) | Make the shared CFS store group-readable and verify it; `--check` reports only, exit 1 if broken (cron-safe) | Called by `update-image.sh` after every pull; by hand after a direct `podman-hpc pull --squash-dir` |
| [install-uv.sh](install-uv.sh) | Install or update `uv` in the shared project bin dir with group-correct permissions | Once, then to update uv — **instead of `uv self update`**, which cuts the rest of the project off |
| [install-jupyter-kernel.sh](install-jupyter-kernel.sh) | Register a Jupyter kernel — container, venv or conda env — so **jupyter.nersc.gov** runs your environment. `--shared` installs project-wide, `--link` adopts those per user; `--list` / `--remove` manage them | Once per environment; `--link` once per user |
| [setup-nionswift-launcher.sh](setup-nionswift-launcher.sh) | One-shot setup of the Nion Swift one-click launcher; detects whether it is on Perlmutter or a ThinLinc host. On Perlmutter it also installs the `nionswift-idrobolab` command; on ThinLinc it gives the desktop folder the group logo (`assets/idrobolab-folder.png` at the top of the repository) | Once per maintainer, once per group member (ThinLinc side) — see [nionswift-perlmutter-thinlinc.md](../../docs/perlmutter/reference/nionswift-perlmutter-thinlinc.md) |

All are idempotent: re-running one is the normal way to update
(`install-jupyter-kernel.sh` wants `--force` to replace an existing kernel).

Two ways to reach a notebook, and they are complements rather than rivals:
`install-jupyter-kernel.sh` puts your environment in **jupyter.nersc.gov** —
no tunnel, nothing to keep open, survives a dropped laptop connection;
[`../jobs/interactive_jupyter.sh`](../jobs/interactive_jupyter.sh) gives you a
session on a node you allocated yourself, running the exact image the batch
jobs use. Both are documented in [jupyter.md](../../docs/perlmutter/reference/jupyter.md).

`update-image.sh` locates `fix-store-perms.sh` relative to its own file, so the
two must stay in this directory together. Everything else here is standalone.

Not in this directory, deliberately:

- [`../env.sh`](../env.sh) — sourced from `~/.bashrc`, not executed. It stays at
  `perlmutter/env.sh` so the source line people already have keeps working.
- `../jobs/interactive_gpu.sh`, `../jobs/interactive_gpu_shared.sh`, `../jobs/interactive_jupyter.sh` — helpers
  rather than `sbatch` templates, but they share the mount/image/QOS
  conventions of the templates they sit beside, and `jobs/README.md`
  documents them in the same matrix.
