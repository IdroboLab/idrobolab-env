# idrobolab-env

The IdroboLab group's environment for NERSC Perlmutter (project <project>): shell
setup, Slurm job templates, the `idrobolab` container recipe, Jupyter and Nion
Swift setup, and the introduction for new group members.

**New here? Start at [perlmutter/docs/README.md](perlmutter/docs/README.md).**

| Path | What |
|---|---|
| [perlmutter/](perlmutter/) | Everything for Perlmutter: `env.sh`, helpers, job templates, reference notes, the step-by-step docs |
| [shared/containers/x86_64-cuda/idrobolab/](shared/containers/x86_64-cuda/idrobolab/) | Recipe for the `idrobolab` container image (`ghcr.io/<username>/idrobolab`) |
| [shared/verification/multigpu_abtem/](shared/verification/multigpu_abtem/) | Payloads for the abTEM multi-GPU verification launched from `perlmutter/verification/` |

## Your own clone

Everyone works from their own clone in their home directory:

```bash
git clone git@github.com:IdroboLab/idrobolab-env.git ~/idrobolab-env
~/idrobolab-env/perlmutter/helpers/setup-user.sh
```

`git -C ~/idrobolab-env pull` brings in updates. GitHub access and SSH keys:
[perlmutter/docs/02-github.md](perlmutter/docs/02-github.md).

## Contributing

`main` is protected: make a branch, push it, open a pull request. Fixes to the
docs are as welcome as fixes to the scripts.

## History

This repo was split out of the `hpcenvs` repo (which keeps the
Delta, LUMI, Dardel and Arrhenius environments and the `otherimage` and
`ruszlab` container recipes); the history of the files kept here came along.
Some identifiers keep the old name so existing setups go on working: the
`# >>> hpcenvs (<project>) >>>` block that `setup-user.sh` writes into your shell
startup file and the `HPCENVS_*` variables in `env.sh`.
