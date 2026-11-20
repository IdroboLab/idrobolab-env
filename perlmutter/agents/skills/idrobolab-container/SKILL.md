---
name: idrobolab-container
description: Running work inside the IdroboLab group image (idrobolab, recipe in idrobolab-env shared/containers/x86_64-cuda/idrobolab) on Perlmutter (podman-hpc) and Delta (Apptainer) — what it contains (GPAW, abTEM, gpaw-weaver editable from /opt/src; CuPy 14.1.1, CUDA 12.9, torch 2.13, dask-cuda, LAMMPS, QE), running a branch of abTEM or GPAW by PYTHONPATH or a bind over /opt/src, checking which copy was imported, running a package's test suite (the image has no pytest; shared/testing/run_pytest.py installs it with the test dependencies; pytest rootdir and package-name shadowing traps), git inside the container, and how it differs from an environment with another CuPy. Use when writing or handing over any command that runs in the idrobolab image, especially tests of an abTEM or GPAW branch on a cluster GPU.
---

# The idrobolab container

Images are pulled by hand by the maintainer: commands reference the image by its full name
(`$IDROBOLAB_IMAGE`, which is `ghcr.io/idrobolab/idrobolab:latest`, under podman-hpc; the `.sif`
path on Delta) and never include a pull or build step. The `perlmutter-cluster` skill has the
Perlmutter launch conventions (Slurm, podman-hpc, the command guard); Delta's are in `docs/delta/README.md` and `delta/AGENTS.md`
in the idrobolab-env clone.
How the image is built and published is its `README.md` in idrobolab-env
(`shared/containers/x86_64-cuda/idrobolab/`); this skill is about using it.

## What is inside

- Python 3.12 venv at `/opt/venv` (first on `PATH`), CUDA 12.9 runtime, MPICH.
- **Editable installs from `/opt/src`:** `gpaw`, `gpaw-weaver`, `abTEM`, as staged at build
  time. Everything else is pinned in `requirements-idrobolab.txt`.
- `cupy-cuda12x` **14.1.1**, torch 2.13.0 (the version fairchem pins), dask-cuda 26.6.0 installed
  `--no-deps`, fairchem, orb-models, ptyrad, phonopy, hiphive, pymatgen, nionswift (headless),
  LAMMPS (Kokkos-CUDA, `/opt/software/lammps`), Quantum ESPRESSO GPU (`/opt/software/qe`),
  `bader`, `git`.
- **No test tooling: no `pytest`, `hypothesis`, or any package's test dependency group.** A
  test command that just calls `python -m pytest` fails with `No module named pytest`.

## Running a branch instead of the baked-in checkout

- Either put a worktree first on `PYTHONPATH` (`-e PYTHONPATH=$WT`), or bind the checkout over
  `/opt/src/<name>`. Print `<pkg>.__file__` in the same container run to show which copy was
  imported.
- **Verify that a bound checkout actually took effect.** The baked tree under `/opt/src/<name>`
  has no `.git` directory, so a bind that silently failed (an unmounted path) falls through to
  the image's own copy and looks like a working one. In the same container run, print
  `git -C /opt/src/<name> rev-parse --short HEAD` (or `baked-image-tree` when it fails), and
  stop with an error unless it is the commit you expected. A plain clone is enough for
  pure-Python branch changes: the container's compiled GPAW extension in site-packages still
  applies.
- **Pin the checkout a queued or array job imports.** Each task imports the source when it
  starts, which can be hours after submission, so switching or pulling that checkout in the
  meantime silently runs later tasks on different code than earlier ones. Point the job at a
  worktree detached at a commit (`git -C <clone> worktree add --detach <dir>/<commit>
  <commit>`), never at a checkout used for other work, and have each task compare the
  checkout's `HEAD` and clean state against the expected commit, passed in at submission, and
  exit 1 on a mismatch. For a newer commit add a second worktree; remove old ones only after
  their jobs have finished.
- **Never name a working or output directory after a package that is editable-installed in the
  image** (`gpaw`, `abtem`, `gpaw_weaver`). `python -c '...'` puts the current directory on
  `sys.path`, so a local `./gpaw` or `./abtem` directory shadows the real install as an empty
  namespace package — a nonsensical `ImportError` for a name that plainly exists. `python -P`
  drops the CWD from `sys.path` for exactly this case; `python path/to/script.py` is immune
  on its own, since Python inserts the *script's* directory, not the CWD.
- A custom directory is visible inside only where it is bound; `$HOME`, `$SCRATCH`,
  `$PSCRATCH` and `$CFS` need their own `-v X:X` on Perlmutter.
- Under rootless podman, git inside the container needs
  `-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'`.

## Running a test suite

Run it through `shared/testing/run_pytest.py` (its README and docstring have the details): it
installs the test dependencies the project declares in its `pyproject.toml` into the
container's own `/opt/venv`, prints which copy of the package Python imports, and runs pytest
with `-p no:cacheprovider` (a read-only checkout cannot take the cache write). Nothing persists
between `podman-hpc run --rm` calls, so every run reinstalls; never install into the image or a
shared venv, and never `pip install -e <checkout>[test]` (a read-only checkout cannot take the
egg-info write). On Delta the install needs a writable layer (`--writable-tmpfs` holds 64 MiB, enough for one
small install; several need an overlay image) and a
`NUMBA_CACHE_DIR` outside the image (`delta-cluster`, *Building and shipping a container image*).

**Leave `OMP_NUM_THREADS` at the image's 1** in every command and launcher that runs the suite
of an abTEM branch older than abTEM PR #705 (merged 2026-11-20). With more, GPAW warns
`Using OMP_NUM_THREADS>1 in PW-mode is not useful!`, and the suite, which turns warnings into
errors, fails its GPAW plane-wave tests; PR #705 filters the warning, and the image's abTEM
includes it. Several Perlmutter job templates set 8 to 32 threads for production runs; a suite
run of an older branch through one sets it back to 1.

pytest's `rootdir` comes from the test path argument, not from the shell's working directory:
pass the absolute, in-container test path (`$WT/test/`, `/opt/src/<package>/test/...`). A
wrong-looking rootdir is not fixed by `--workdir` or by `cd`.

abTEM on Perlmutter for a worktree `$WT`, first the allocation (the shell lands on the compute
node), then the run (`${WT:?}` stops the command when `WT` is unset; without it `--workdir`
vanishes, podman takes the image name for the working directory and pulls `python:latest`):

```bash
salloc -C gpu -q shared_interactive -A "$NERSC_PROJECT" -t 00:30:00 -n 1 -c 32 --gpus-per-task=1 -L scratch,cfs
srun podman-hpc run --rm --group-add keep-groups --gpu -v $CFS:$CFS -v $SCRATCH:$SCRATCH -v $HOME:$HOME -e PYTHONPATH=${WT:?} --workdir $WT ghcr.io/idrobolab/idrobolab:latest python ~/idrobolab-env/shared/testing/run_pytest.py $WT/test/ -k gpu -m "not multigpu" -q -rfE --tb=short 2>&1 | tail -30
```

The repo's sbatch templates (`perlmutter/jobs/`) pass no `PYTHONPATH`, so a batch run through
them tests the image's own copy, unless the template's `MOUNTS` line binds a checkout over
`/opt/src/<name>`; the import path `run_pytest.py` prints shows which copy ran.

## Versus an environment with another CuPy

The image carries CuPy 14.1.1. An environment with CuPy 13.5.1 (or an older `amd-cupy` ROCm
build) is not this image, and a result from one does not stand for the other:
CuPy 14 compiles `RawModule` kernels through CCCL and needs C++17, 13.5.1 does not. Say which
environment and CuPy version a GPU result came from.
