# idrobolab-env

The IdroboLab group's environments for NERSC Perlmutter and NCSA Delta:
shell setup, Slurm job templates, the `idrobolab` container recipe, Jupyter and Nion
Swift setup on Perlmutter, and the documentation for new group members.

**New here? Start at [docs/README.md](docs/README.md)**: GitHub, cloning and Globus
first, then the step-by-step Perlmutter introduction or the Delta page.

| Path | What |
|---|---|
| [docs/](docs/) | All documentation: the general pages ([GitHub](docs/01-github.md), [cloning](docs/02-cloning.md), [Globus](docs/03-globus.md)), [contributing](docs/CONTRIBUTING.md), the Perlmutter introduction and reference notes in [docs/perlmutter/](docs/perlmutter/), and the Delta page in [docs/delta/](docs/delta/README.md) |
| [perlmutter/](perlmutter/) | The files for Perlmutter: `env.sh`, helpers, job templates, examples, agent rules |
| [delta/](delta/) | The files for Delta (NCSA): `env.sh`, the setup helper, `get-image.sh`, job templates per partition, the multi-GPU verification launchers, agent rules |
| [windows/idrobolab-uploads/](windows/idrobolab-uploads/) | The IdroboLab Uploads tool for the Windows measurement PCs: upload folders, files or a Nion Swift project to the group's Google Drive (PowerShell script, installer, README) |
| [assets/](assets/) | The IdroboLab logo and the icons made from it (ThinLinc folder, upload tool), under CC BY 4.0 with their own copyright holder ([license](assets/LICENSE)) |
| [shared/containers/x86_64-cuda/idrobolab/](shared/containers/x86_64-cuda/idrobolab/) | Recipe for the `idrobolab` container image (`ghcr.io/idrobolab/idrobolab`) |
| [core/](core/) | Vendored copy of [hpcenv-core](https://github.com/pzeiger/hpcenv-core) (shared shell helpers for the `setup-user.sh` scripts, the `sbatch`/`salloc` account functions, the personal-data check, the LAMMPS GPU self-test). Never edited here, see [Shared code: `core/`](#shared-code-core) |
| [shared/verification/multigpu_abtem/](shared/verification/multigpu_abtem/) | Payload for the abTEM multi-GPU verification launched from `perlmutter/verification/` and `delta/verification/` |

## Shared code: `core/`

`core/` is an exact copy of one commit of hpcenv-core, the code several of the group's
environment repositories share; `core/CORE_COMMIT` holds that commit's SHA. Nothing in `core/` is
edited here: a change goes to hpcenv-core by pull request and arrives with the next sync. To move
to another hpcenv-core commit, from the top of a clone, on a branch:

```bash
core/sync/sync-core.sh main        # or a tag or a full commit SHA; replaces core/, commits nothing
git add core && git commit -m "core: update hpcenv-core"
core/sync/sync-core.sh --check     # exit 1, naming the paths, if core/ differs from CORE_COMMIT
```

The workflows in `.github/workflows/` run `--check` on every pull request (`core-drift`), run the
personal-data check (`personal-data`; exceptions are in `personal-data-allow.txt`, each with its
reason) and open a pull request when hpcenv-core `main` moves (`core-sync`, weekly; it needs the
setting "Allow GitHub Actions to create and approve pull requests"). The `account-kinds` workflow
checks the job templates of `perlmutter/jobs/` and `delta/jobs/` (see
[Perlmutter jobs](perlmutter/jobs/README.md#sbatch-and-salloc-add-the-account) and
[Delta](docs/delta/README.md#sbatch-and-salloc-add-the-account)).

## Your own clone

Everyone works from their own clone in their home directory. On Perlmutter, `setup-user.sh`
then sets up the shell (on Delta the script is `delta/helpers/setup-user.sh`; see [docs/delta/](docs/delta/README.md)):

```bash
git clone git@github.com:IdroboLab/idrobolab-env.git ~/idrobolab-env
~/idrobolab-env/perlmutter/helpers/setup-user.sh
```

`git -C ~/idrobolab-env pull` brings in updates. GitHub access and SSH keys:
[docs/01-github.md](docs/01-github.md); cloning: [docs/02-cloning.md](docs/02-cloning.md).

## Contributing

Every change reaches `main` through a pull request, which a member of the `env-reviewers` team
approves and an admin merges.
Fixes to the docs are as welcome as fixes to the scripts: see
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

Copyright (c) 2026, University of Washington, except `perlmutter/agents/nersc/` and
`assets/`.

- The scripts, job templates, container recipe, agent instructions and everything else
  outside `docs/`, `assets/` and `perlmutter/agents/nersc/` are under the
  [BSD 3-Clause License](LICENSE).
- The documentation in `docs/` is under
  [Creative Commons Attribution 4.0 International](docs/LICENSE) (CC BY 4.0). The
  commands and code snippets in it may also be used under the BSD 3-Clause License, so
  they can be copied into scripts without attribution.
- The files in `perlmutter/agents/nersc/` are NERSC's and keep their own
  [BSD 3-Clause License](perlmutter/agents/nersc/LICENSE).
- The files in `core/` are hpcenv-core's and keep its licenses: code under
  [BSD 3-Clause](core/LICENSE), `core/docs/` under [CC BY 4.0](core/docs/LICENSE).
- The IdroboLab logo and the icons made from it, in `assets/`, are copyright (c) 2026,
  IdroboLab, and under [Creative Commons Attribution 4.0 International](assets/LICENSE)
  (CC BY 4.0).
- The licenses above cover the group's own files only. The NVIDIA components of the
  `idrobolab` container image keep their own terms, recorded in
  [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md).

The third-party material in the repository, with its sources and licenses, is listed in
[docs/THIRD-PARTY.md](docs/THIRD-PARTY.md).

## History

This repo was split out of the `hpcenvs` repo: its Perlmutter and Delta directories moved
here with their history, and `hpcenvs` holds nothing this repo needs any more.
The `# >>> idrobolab-env >>>` block that `setup-user.sh` writes into your shell
startup file and the `IDROBOLAB_ENV_*` variables were `hpcenvs` and `HPCENVS_*` before the
split. The old marker (also with the project in it, `idrobolab-env (<project>)`) is still
recognised, so existing setups go on working; the old variables are not.
