# Delta (NCSA)

How to work on NCSA's Delta HPC system (x86_64; AMD Milan CPUs, with Intel Xeon on the
H200 nodes; NVIDIA A40/A100/H200 GPUs; Slingshot 11 interconnect; Slurm + Cray MPICH;
containers via Apptainer). The files for Delta are in [`delta/`](../../delta/); this page
is the overview, [`delta/jobs/README.md`](../../delta/jobs/README.md) holds the partition
matrix, the MPI launch guide and the first-run checklist, and
[`delta/AGENTS.md`](../../delta/AGENTS.md) the conventions and traps that cost time on
Delta (environment variables, where files live, the editable-install import trap).

## Where things are

| Path | Purpose |
|---|---|
| [delta/env.sh](../../delta/env.sh) | Shell setup, sourced from `~/.bashrc`: `SCRATCH_BASE` and `PROJECTS_BASE`, Apptainer cache on personal scratch, uv cache shared by the project |
| [delta/helpers/setup-user.sh](../../delta/helpers/setup-user.sh) | Per-user setup: writes the `~/.bashrc` lines for `env.sh`, creates the Apptainer cache directory, reports what is missing (`--check`, `--undo`) |
| [delta/get-image.sh](../../delta/get-image.sh) | Materialize the Delta `.sif` from the published registry image (from a login node it queues itself on `cpu-interactive`; needs `ACCOUNT=<project>-delta-cpu`) |
| [delta/jobs/](../../delta/jobs/) | Slurm submission templates per partition (cpu single/multi-node MPI, A40/A100/A100x8/H200 GPU, interactive helper); its README has the partition matrix and the MPI launch guide |
| [delta/verification/](../../delta/verification/) | On-node checks: [multi-GPU abTEM](../../delta/verification/multigpu_abtem/README.md) (launchers; the Python payloads are shared with Perlmutter in [`shared/verification/multigpu_abtem/`](../../shared/verification/multigpu_abtem/)) |
| [delta/AGENTS.md](../../delta/AGENTS.md) | Conventions for Delta, read by coding agents (`delta/CLAUDE.md` imports it) |

## Getting started

1. Run `accounts` on a Delta login node to find your charge accounts: `<project>-delta-cpu` for the CPU partitions, `<project>-delta-gpu` for the GPU partitions, charged separately.
2. Clone this repository to `~/idrobolab-env` on Delta, as described in [general page 2](../02-cloning.md).
3. Set up your shell, once, on a login node:
   ```bash
   ~/idrobolab-env/delta/helpers/setup-user.sh
   ```
   It finds your project (the `<project>` of your accounts from step 1; `--project <project>` names it when it cannot, for example when you are in several projects), adds a marked block to `~/.bashrc`, creates your Apptainer cache directory, and reports what is still missing. `--check` only reports, `--undo` removes the block again, and `--github-email ADDRESS` makes your commits in GitHub repositories carry your GitHub noreply address ([general page 1](../01-github.md#keeping-your-address-out-of-public-commits)); the report warns when they carry another one. Log in again afterwards. The block holds these two lines, the second with the path of your clone:
   ```bash
   export DELTA_PROJECT=<project>
   if [ -r "<clone>/delta/env.sh" ]; then . "<clone>/delta/env.sh"; fi
   ```
   The second line sources [`delta/env.sh`](../../delta/env.sh). It sets `SCRATCH_BASE` (`/scratch/<project>`) and `PROJECTS_BASE` (`/projects/<project>`), which the job templates and `get-image.sh` read and Delta does not define, keeps the Apptainer cache on your scratch (`$SCRATCH_BASE/$USER`) instead of your home quota, and points uv at the project's [shared cache](#the-shared-cache) once an admin has created it, and puts the group's [uv](#uv) on your `PATH`. `IDROBOLAB_ENV_VERBOSE=1 . ~/idrobolab-env/delta/env.sh` prints what it set; if the `SCRATCH_BASE` line reads `<unset>`, `DELTA_PROJECT` is not exported above the line that sources the file, is mistyped, or `/scratch/<project>` does not exist on that node. A `SCRATCH_BASE` or `PROJECTS_BASE` you set yourself takes precedence.
4. Build the image once, on a login node (it queues the conversion on a compute node itself, because the conversion is too heavy for a login node):
   ```bash
   mkdir -p $PROJECTS_BASE/software/containers && ACCOUNT=<project>-delta-cpu SIF=$PROJECTS_BASE/software/containers/idrobolab.sif ~/idrobolab-env/delta/get-image.sh
   ```
   The `.sif` lands in `$PROJECTS_BASE/software/containers/`, where the job templates look for it, not in scratch. Record `sha256sum` of the image with your results. The script pulls the group image `ghcr.io/idrobolab/idrobolab` by default; if it stops with `unauthorized`, ask an admin (see [The images](#the-images)).
5. Copy the job template for your partition from [`delta/jobs/`](../../delta/jobs/), replace `<project>` in its `--account` line, and submit it with your script as the argument: `sbatch gpu_a100_1gpu.sbatch my_script.py`. Always set `--time`: the default is 30 minutes.
6. Run the smoke tests of the [first-run checklist](../../delta/jobs/README.md#first-run-checklist) once before the first real job.

## uv

[uv](https://docs.astral.sh/uv/) is not installed on Delta. The group keeps one copy in the project's shared bin directory, `$PROJECTS_BASE/software/bin`, which `delta/env.sh` puts on your `PATH` once it exists. An admin installs it once, on a login node, and repeats the same commands to update it:

```bash
BIN="$PROJECTS_BASE/software/bin"
GRP="$(stat -c %g "$PROJECTS_BASE")"
mkdir -p "$BIN"
chgrp "$GRP" "$BIN"
chmod 2750 "$BIN"
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="$BIN" UV_NO_MODIFY_PATH=1 sh
chgrp "$GRP" "$BIN"/uv "$BIN"/uvx
chmod 750 "$BIN"/uv "$BIN"/uvx
"$BIN"/uv --version
ls -ld "$PROJECTS_BASE/software" "$PROJECTS_BASE/software/containers" "$BIN" "$BIN"/uv "$BIN"/uvx
```

`UV_NO_MODIFY_PATH=1` keeps the installer from editing the admin's own shell files; `env.sh` already handles `PATH` for everyone. The `chgrp` and `chmod` after the install matter: the installer writes the binaries with the admin's own group and `umask`, which can leave them unusable for the other members. For the same reason, don't run `uv self update`: it replaces the shared binary the same way. The listing must show the project's group on every line, with `r-x` for it on the two binaries (`r-s` on the setgid bin directory). The images go to `software/containers`, which members must be able to write to, or to create in `software` while it does not exist. Log in again (or source `env.sh`) and check with `uv --version`.

### The shared cache

`delta/env.sh` sets `UV_CACHE_DIR` to `$SCRATCH_BASE/uv-cache`, one cache for the whole project, so a package one member has downloaded is not downloaded again by the next. An admin creates the directory once:

```bash
mkdir "$SCRATCH_BASE/uv-cache"
chgrp "$(stat -c %g "$SCRATCH_BASE")" "$SCRATCH_BASE/uv-cache"
chmod 2770 "$SCRATCH_BASE/uv-cache"
setfacl -d -m u::rwx,g::rwx,o::--- "$SCRATCH_BASE/uv-cache"
```

The setgid bit keeps everything inside in the project's group, and the default ACL makes what uv creates there writable by the group whatever the member's `umask` is; without it uv follows the `umask`, and files written under a private one lock the other members out. Until the directory exists and is writable for you, `env.sh` keeps your cache at `$SCRATCH_BASE/$USER/uv-cache`.

With the shared cache `env.sh` also sets `UV_LINK_MODE=copy`, so an environment holds its own copies of the packages and never hard links to the cache's files, which older uv versions make by default. Every member of the project can write to the cache, so install only what you would run from a colleague's directory.

## The images

The templates default to the group's `idrobolab` image (`ghcr.io/idrobolab/idrobolab`): GPAW, abTEM and gpaw-weaver, with ptyrad, nionswift, fairchem, orb-models and phonopy, on CUDA 12.8 and Python 3.12. Its recipe is in [`shared/containers/x86_64-cuda/idrobolab/`](../../shared/containers/x86_64-cuda/idrobolab/), and its package is public, so `delta/get-image.sh` needs no credentials; if it fails with `unauthorized`, ask an admin. **The idrobolab image has not been run on Delta yet**: work through the [first-run checklist](../../delta/jobs/README.md#first-run-checklist) before a real job. The templates take any other image through `SIF=/path/to/image.sif`. One image serves A40, A100 and H200 nodes: the Python GPU wheels (torch, cupy) and MAGMA cover Ampere and Hopper, while the QE GPU build targets sm_80 and LAMMPS is built for AMPERE80, relying on PTX JIT on H200.

## Conventions

- Built container images (`*.sif`), build logs and staged source trees (`src/`) are **not** tracked, only the recipes that reproduce them.
- Source checkouts that override the image's editable packages are project-scoped (`<project-dir>/code/<name>` on `/projects`, bound over `/opt/src/<name>`); job output and other regenerable bulk goes to `$SCRATCH_BASE/$USER/...`. Details and the reasons are in [`delta/AGENTS.md`](../../delta/AGENTS.md).
- Delta jobs are charged to an allocation: 1 SU is one core-hour or one GPU-hour, `-interactive` queues cost twice their batch partition, `-preempt` half. The charge factors per partition are in the [partition matrix](../../delta/jobs/README.md#script--partition-matrix).
