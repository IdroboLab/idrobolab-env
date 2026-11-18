# idrobolab-env: instructions for coding agents

The IdroboLab group's environments: NERSC Perlmutter in `perlmutter/`
(env.sh, helpers, job templates) and NCSA Delta in `delta/` (env.sh, get-image.sh, job templates,
verification launchers), the `idrobolab` container recipe under
`shared/containers/x86_64-cuda/idrobolab/`, and the documentation in `docs/`. Split out of
the `hpcenvs` repo, which is frozen and holds nothing this repo needs. Rules specific to
one cluster are scoped to it below; `delta/AGENTS.md` holds the Delta conventions.

This file is read by every coding agent (Codex reads `AGENTS.md` directly; Claude Code
through `CLAUDE.md`, which imports it). Keep agent instructions here, not in `CLAUDE.md`.

## Git workflow

- **Never push to `main`, and never commit on it.** Every change (feature, addition, fix,
  docs) goes on a branch and reaches `main` through a pull request that an admin merges.
  A ruleset on `main` enforces the pull request: it needs an approval from the
  `env-reviewers` team and passing `personal-data`, `drift`, `perlmutter` and `delta`
  checks, because whatever reaches `main` reaches every member's shell on their next pull.
  The member-facing workflow is `docs/CONTRIBUTING.md`.
- All documentation lives in `docs/`: the general pages (`01-github.md`, `02-cloning.md`,
  `03-globus.md`), `CONTRIBUTING.md`, `THIRD-PARTY.md`, the Perlmutter section `docs/perlmutter/`, with
  its reference notes in `docs/perlmutter/reference/`, and the Delta page
  `docs/delta/README.md`. The general and Perlmutter series are numbered in reading
  order, so renaming or adding a page means updating every `[page N]` link and the tables
  in `docs/README.md` and `docs/perlmutter/README.md`. The README of a directory that
  holds scripts (`perlmutter/jobs/`, `perlmutter/helpers/`, `delta/jobs/`, ...) stays next
  to them, and a cluster's narrative goes in its `docs/<cluster>/` page; `delta/README.md`
  is a short directory README pointing to `docs/delta/README.md`.
- Each member works from their own clone (`~/idrobolab-env`, or wherever they cloned it);
  nothing reads a shared checkout. Scripts locate their siblings relative to their own
  file, and docs give paths as `~/idrobolab-env/...`.
- `git config pull.rebase true` in each clone; keep history linear.

## uv

- On Perlmutter and Delta, members use the group's uv from the project's shared bin
  directory, which `env.sh` puts on `PATH`. Docs, scripts and agent advice never tell them
  to install their own (uv's installer, `~/.local/bin/uv`) or to run `uv self update`; only
  an admin installs or updates the shared binary (`perlmutter/helpers/install-uv.sh`, the
  Delta steps in `docs/delta/README.md`).

## perlmutter/env.sh and setup-user.sh

- Existing members run `perlmutter/helpers/setup-user.sh` once after updating their clone:
  `env.sh` has no default project, and the script adds `export NERSC_PROJECT=<project>`
  to their block, taking the project from the old marker. Say so in the text of any
  change that touches this.
- `env.sh` is sourced from `~/.bashrc` and must stay silent, idempotent and inert off
  Perlmutter: respect pre-set values (`: "${VAR:=default}"`), guard every derivation on
  the variables it depends on, never `exit` or `set -e`.
- `setup-user.sh` writes a marked block into the user's startup file. The markers
  `# >>> idrobolab-env >>>` / `# <<< idrobolab-env <<<` and the `IDROBOLAB_ENV_*` variables
  replace the `hpcenvs` marker and `HPCENVS_*` variables from before the rename, and the
  markers that named the project (`# >>> idrobolab-env (<project>) >>>`). `setup-user.sh`
  renames an old marker on a rerun (and still removes one with `--undo`); the scripts no
  longer read the old `HPCENVS_*` variables.
- The NERSC project has no default anywhere in the repository: `setup-user.sh` writes
  `export NERSC_PROJECT=<project>` into the block, `env.sh` sets nothing that depends on it
  while it is unset, and the scripts that need it stop with a message naming the variable.
  Write `<project>` in templates, docs and examples, never a real ID.
- **Account.** `env.sh` exports `HPCENV_ACCOUNT_*` from `NERSC_PROJECT` (one account for CPU and
  GPU jobs, no `_g`, no GPU partitions) and sources `core/shell/accounts.sh`, inside the
  Perlmutter guard; the templates keep their `--account=<project>` placeholder. A new
  `perlmutter/jobs/*.sbatch` gets a `cpu`/`gpu` line in `perlmutter/jobs/account-kinds.txt` (the
  `account-kinds` workflow checks it).

## core/ (vendored hpcenv-core)

- `core/` is a vendored copy of one hpcenv-core commit (`core/CORE_COMMIT`): never edit it here. A
  change goes to hpcenv-core by pull request and arrives through `core/sync/sync-core.sh <ref>`
  (the `core-sync` workflow proposes it weekly). The `--github-email` helper
  (`core/shell/github-identity.sh`, sourced by both `setup-user.sh` scripts), the common part of
  Delta's `setup-user.sh` (`core/shell/setup-user-common.sh`), the `sbatch`/`salloc` account
  functions and `lammps-gpu-selftest.sh` live there only. `perlmutter/helpers/setup-user.sh` sources
  `github-identity.sh` and nothing else of the common part (its undo covers two startup files and
  older marker names).
- No personal data in this repository: `python3 core/checks/personal_data.py` runs in CI and an
  exception goes into `personal-data-allow.txt` with a reason. The repository is public and a
  pushed branch is visible at once, before any review: run the check on the committed state
  before every push.

## Delta (delta/)

- The job templates default `SIF` to `$PROJECTS_BASE/software/containers/idrobolab.sif`
  (`get-image.sh` pulls `ghcr.io/idrobolab/idrobolab` into it; on Delta that image has so far
  run only a 2-node MPI hello-world). Account handling is in `delta/AGENTS.md`.
- The Python payload of the multi-GPU verification is shared with Perlmutter in
  `shared/verification/multigpu_abtem/`; the launchers in `delta/verification/` and
  `perlmutter/verification/` locate it relative to themselves. Change the payload once,
  there.
- Read `delta/AGENTS.md` before editing anything in `delta/`.

## Agent instructions (perlmutter/agents/)

`perlmutter/agents/` holds the rules `helpers/setup-agents.sh` installs for members' agents
(`group.md`) and the skills it links into their skills folders (`skills/<name>/SKILL.md`: the
directory name is the skill's `name`, the `description` stays under 1024 characters and
carries the trigger words, no reference to private skills or to files outside the clone). The
Delta skill, `delta-cluster`, lives there too, so that the one script links every skill. The
vendored `nersc/` files change only through `sync-nersc.sh` or the `nersc-agents-sync`
workflow, never by hand.

## The idrobolab container recipe

- The image is built and pushed (`publish.sh` → `ghcr.io/idrobolab/idrobolab`) only from the
  maintainer's devcontainer, where `prepare_build_context.sh` stages the editable trees
  from `CODE_DIR=/workspaces/code`. Nobody builds on Perlmutter. `publish.sh` and
  `release.sh` stop unless `GHCR_USER` and `GITHUB_PACKAGE_TOKEN` are set in the shell that
  runs them: a build or release command handed to the maintainer sets `GHCR_USER` too.
- `:latest` and `:<N>` (N = `VERSION`) move only at a release, by `release.sh`, after the
  verification suite passed on `:<N>-rc`; never retag or move them otherwise. `publish.sh`
  pushes `<VERSION>-rc` (or `TAG=dev`).
- `src/` staging dirs are generated by `prepare_build_context.sh` and never committed
  (git-ignored as `shared/containers/**/src/`). So is `lammps-gpu-selftest.sh`: the script
  stages it from `core/lammps/` for the Dockerfile's `COPY`, and `publish.sh` refuses to build
  when the staged file is missing or differs.
- All three source trees are staged from committed files with `git archive`, never from
  a working tree (the script's header says why), at the commits `sources.txt` names; a commit
  on no remote-tracking branch fails the staging. A development build edits `sources.txt`,
  which makes the recipe `dirty`: no release candidate.
  Other branches run by a bind mount over `/opt/src/<name>`.
- MPI stays MPICH-ABI (`libmpi.so.12`). The image is x86_64-cuda: never point it, or
  anything compiled in it, at another architecture.
- The image has no test tooling: test suites run through `shared/testing/run_pytest.py`, which
  installs the project's declared test dependencies into the throwaway container.
- Record the image digest (`podman-hpc images --digests` on Perlmutter, `sha256sum` of the
  `.sif` on Delta) with campaign results.
