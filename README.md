# idrobolab-env

The IdroboLab group's environments for NERSC Perlmutter (project <project>) and NCSA Delta:
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
| [shared/helpers/](shared/helpers/) | Code the clusters' `setup-user.sh` scripts share: the git address for GitHub repositories (`--github-email`) |
| [shared/verification/multigpu_abtem/](shared/verification/multigpu_abtem/) | Payloads for the abTEM multi-GPU verification launched from `perlmutter/verification/` and `delta/verification/` |

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

Every change reaches `main` through a pull request, which an admin reviews and merges.
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
- The IdroboLab logo and the icons made from it, in `assets/`, are copyright (c) 2026,
  IdroboLab, and under [Creative Commons Attribution 4.0 International](assets/LICENSE)
  (CC BY 4.0).

## History

This repo was split out of the `hpcenvs` repo: its Perlmutter and Delta directories moved
here with their history, and `hpcenvs` holds nothing this repo needs any more.
The `# >>> idrobolab-env (<project>) >>>` block that `setup-user.sh` writes into your shell
startup file and the `IDROBOLAB_ENV_*` variables were `hpcenvs` and `HPCENVS_*` before the
split. The old marker and the old variables are still recognised, so existing setups go on
working.
