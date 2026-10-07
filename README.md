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
| [delta/](delta/) | The files for Delta (NCSA): `get-image.sh`, job templates per partition, the multi-GPU verification launchers, agent rules |
| [shared/containers/x86_64-cuda/idrobolab/](shared/containers/x86_64-cuda/idrobolab/) | Recipe for the `idrobolab` container image (`ghcr.io/<username>/idrobolab`) |
| [shared/verification/multigpu_abtem/](shared/verification/multigpu_abtem/) | Payloads for the abTEM multi-GPU verification launched from `perlmutter/verification/` and `delta/verification/` |

## Your own clone

Everyone works from their own clone in their home directory. On Perlmutter, `setup-user.sh`
then sets up the shell (Delta has no setup script; see [docs/delta/](docs/delta/README.md)):

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

## History

This repo was split out of the `hpcenvs` repo: its Perlmutter and Delta directories moved
here with their history, and `hpcenvs` holds nothing live any more.
Some identifiers keep the old name so existing setups go on working: the
`# >>> hpcenvs (<project>) >>>` block that `setup-user.sh` writes into your shell
startup file and the `HPCENVS_*` variables in `env.sh`.
