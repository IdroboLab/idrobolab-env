# Running test suites in the idrobolab container

The image has no pytest and none of the test dependencies of the packages it carries.
`run_pytest.py` installs the test dependencies the project under test declares in its
`pyproject.toml` (the `test` dependency group, or else the `test` optional dependencies)
into the throwaway container (pytest alone for a project that declares none), prints
which copy of the package Python imports, and runs pytest with the arguments it is given. Its docstring explains each step.

On Perlmutter, for a checkout or worktree `$WT` of abTEM: first a GPU allocation (`srun` with
a GPU does not run without one; the shell lands on the compute node), then the run:

```bash
salloc -C gpu -q shared_interactive -A <account> -t 00:30:00 -n 1 -c 32 --gpus-per-task=1 -L scratch,cfs
export WT=<path to the checkout>
srun podman-hpc run --rm --group-add keep-groups --gpu -v $SCRATCH:$SCRATCH -v $CFS:$CFS -v $HOME:$HOME \
    -e PYTHONPATH=${WT:?} --workdir $WT ghcr.io/idrobolab/idrobolab:latest \
    python ~/idrobolab-env/shared/testing/run_pytest.py $WT/test/ -k gpu -m "not multigpu" -q -rfE --tb=short
```

The working directory is the project (`--workdir $WT`); from anywhere else, pass
`--project <dir>` before the pytest arguments. With `--project`, pass the test path as an
absolute path: pytest finds the rootdir and its configuration from it. `${WT:?}` stops the
command when `WT` is unset; without it podman takes the image name for the working directory
and `python` for the image, and pulls `python:latest` from Docker Hub.
