# Delta (NCSA) — conventions

Environment setup for NCSA's Delta HPC system (Apptainer container + Slurm job
templates for the idrobolab container; on Delta that image has so far
run only a 2-node MPI hello-world).
Rules for editing the files in `delta/`; the member-facing page is
`docs/delta/README.md`, the partition matrix and MPI launch guide are in
`delta/jobs/README.md`. The repo-wide rules are in the root `AGENTS.md`.

## Environment variables — `$SCRATCH` exists only inside jobs

`delta/env.sh` defines **`$SCRATCH_BASE` (= `/scratch/<project>`) and `$PROJECTS_BASE`
(= `/projects/<project>`)** from the member's `DELTA_PROJECT`. Delta sets `$SCRATCH` and
`$WORK` only inside a job, never in a login shell, so scripts here do not use them.
The personal scratch area is `$SCRATCH_BASE/$USER`.
Any script that expands an unguarded `$SCRATCH` under `set -u` aborts.
Never emit `$SCRATCH` in Delta job scripts.

## Container image (SIF) location

Container images live in **`$PROJECTS_BASE/software/containers/`** — NOT in
scratch. Every script defaults `SIF` to
`$PROJECTS_BASE/software/containers/idrobolab.sif`; override per-invocation
with `SIF=/path/to/image.sif <script>`.

When adding or editing a script that references the image, use
`${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/idrobolab.sif`
as the default.

## Environment file

`delta/env.sh` is sourced from `~/.bashrc`, below the member's `export DELTA_PROJECT=<project>`,
and follows the rules for `perlmutter/env.sh` in the root `AGENTS.md`: silent, idempotent,
inert while `DELTA_PROJECT` is unset or names no directory under `/scratch`, pre-set values
respected, every derivation guarded on the variables it depends on, never `exit` or
`set -e`. `delta/helpers/setup-user.sh` writes both lines as a block between the markers
`# >>> idrobolab-env (delta) >>>` and `# <<< idrobolab-env (delta) <<<`, which `--undo`
removes; keep the markers stable. The project name stays out of the repo: write `<project>`. Cluster-wide variables
go there, not into job scripts.

`delta/env.sh` also exports `HPCENV_ACCOUNT_*` (`{project}-delta-cpu`, `{project}-delta-gpu`,
partitions `gpu*`) from `DELTA_PROJECT` and sources `core/shell/accounts.sh`, both inside the
guard; the variables stay exported because `jobs/interactive_gpu.sh` and `get-image.sh` source
`accounts.sh` themselves and default their account from `hpcenv_account`. The job templates keep the
placeholder `<project>-delta-{cpu,gpu}` in their `--account` lines, as do the verification
launchers (not in the tables). A new `jobs/*.sbatch` gets a `cpu` or `gpu` line in
`jobs/account-kinds.txt`; the `account-kinds` workflow checks the listed templates.

## What lives where

- **Container images** → `$PROJECTS_BASE/software/containers/` (shared, provenance
  via `sha256sum`; `*.sif` is not tracked — only the build recipe, the idrobolab recipe under
  `shared/containers/x86_64-cuda/idrobolab/`).
- **Apptainer cache** → `$SCRATCH_BASE/$USER/.apptainer`, per member; **uv cache** →
  `$SCRATCH_BASE/uv-cache`, shared by the project (setgid, default ACL; created once by an
  admin, see `docs/delta/README.md`), with `$SCRATCH_BASE/$USER/uv-cache` until it exists and
  is writable for the member.
  Both are set by `delta/env.sh` (keep off `$HOME`; do not move to projects).
- **Shared tools** (the `uv` binary) → `$PROJECTS_BASE/software/bin`, installed by an admin
  (`docs/delta/README.md`) and put on `PATH` by `delta/env.sh`.
- **Source checkouts are project-scoped**: `<project-dir>/code/<name>` on
  /projects (e.g. `/projects/<project>/<user>/<campaign>/code/gpaw`),
  bound over the image's editable `/opt/src/<name>` — test code belongs to
  the campaign using it, never to a shared cross-project location. Job
  outputs and other regenerable bulk → `$SCRATCH_BASE/$USER/...`.

## Editable-install import trap — never name a dir after a package

The image installs gpaw / gpaw-weaver / abTEM as **editable**
(namespace-style finder), so a directory named after one of them in your
current directory **shadows the real package**. `python -c` puts the CWD on
`sys.path`; Python then treats `./gpaw` as a namespace package, the real
`gpaw/__init__.py` never runs, and imports fail with e.g.
`cannot import name 'GPAW_NO_C_EXTENSION' from 'gpaw' (unknown location)`.

- Do not create working/output directories named `gpaw`,
  `gpaw_weaver`, or `abtem`. Branch-override checkouts go to
  `<project-dir>/code/<name>` (bound to `/opt/src/<name>`) — the `code/`
  level keeps them out of any run CWD.
- For `python -c` preflight checks, use `python -P` (drops CWD from
  `sys.path`). Never add `-P` to `python path/script.py` runs — it also
  drops the script's own dir and breaks sibling imports. Normal
  `python path/script.py` runs are immune (sys.path[0] = script dir, not CWD).
- In-container MPI must use `mpiexec -bootstrap fork` (no outer `srun`);
  without it Hydra tries the host `srun`, absent in the container. Multi-node
  uses the `srun --mpi=pmi2 apptainer exec … python` host-launcher instead.

## Agent skill

NCSA policy (partitions, charge factors, file-system constraints) and measured failure
modes (the MPICH shared-memory collective truncation and its fix) are in the `delta-cluster`
skill, `perlmutter/agents/skills/delta-cluster/SKILL.md`. Keep each rule in one place: the
conventions here, policy and gotchas there.
