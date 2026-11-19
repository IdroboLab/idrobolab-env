# 5. Python with uv

**First choice for GPU work and the big science stack (abTEM, GPAW, torch, CuPy, …):
the group container** ([page 6](06-containers.md)), where everything is already
installed and tested. Use uv for your own analysis code, small tools, and anything the
container doesn't have (abTEM from your own environment: [page 7](07-abtem.md#route-2-your-own-uv-environment)).

[uv](https://docs.astral.sh/uv/) installs Python itself and packages, much faster than
pip or conda. After the group setup ([page 2](02-shell-setup.md#4-group-environment))
it is on your `PATH` and already configured: Python interpreters come from a group
folder everyone can read, and the cache goes on `$SCRATCH`. Check with `uv --version`.

**Python versions:** `uv python list --only-installed` shows the interpreters in the
group folder (3.13 is there). Members can't write to that folder, so if you need
another version, ask the maintainer to install it.

- **Install from a login node.** `/global/common` is read-only on compute nodes, and
  compute nodes should not have to download anything. Run a script once on a login
  node (or `uv sync` a project) before submitting jobs that use it.
- **Don't run `uv self update`.** The `uv` binary is shared by the group, and only
  the maintainer updates it (`helpers/install-uv.sh`).
- Don't mix in `pip install --user` or `conda init`; one tool keeps environments
  reproducible.

## Three ways to use it

**1. A single script with its dependencies inside it.** Good for analysis and plotting
scripts. Start the file with:

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "matplotlib", "hyperspy"]
# ///
import numpy as np
...
```

```bash
uv run --script plot_spectra.py         # builds a cached environment on first run
uv add --script plot_spectra.py scipy   # adds a dependency to the header
```

**2. A project** with its own environment, for code you develop over time:

```bash
uv init myproject && cd myproject       # pyproject.toml + git repo
uv add numpy ase abtem                  # installs into myproject/.venv, records uv.lock
uv run python analyse.py                # runs in that environment
```

Commit `pyproject.toml` and `uv.lock`. On another machine, `uv sync` rebuilds the
identical environment.

**3. A plain virtual environment**, e.g. for a Jupyter kernel or a long-lived
toolbox:

```bash
uv venv --python 3.13 ~/venvs/analysis
uv pip install -p ~/venvs/analysis numpy scipy matplotlib ipykernel
source ~/venvs/analysis/bin/activate    # or call ~/venvs/analysis/bin/python directly
```

## Where environments live

| Where | When |
|---|---|
| `$HOME` (`~/venvs/`, or `.venv` inside a project in `$HOME`) | personal environments: backed up, 40 GB |
| `/global/common/software/<project>/venvs/` | environments for the whole group. Ask first: the folder has a 10 GB quota shared by everyone. |
| not `$SCRATCH` | purged after 8 weeks |
| not CFS | slow for the thousands of small files Python imports |

**Jobs on compute nodes: build the environment in memory at the start of the job.**
`uv run --script` keeps the script's environment in the uv cache, on `$SCRATCH` (Lustre), which
handles the thousands of small files Python reads at import badly. On a busy shared node a
numpy/scipy job importing from there produced no output in 30 minutes; with its packages copied
to `/dev/shm` the same run finished in 7 (2026-11-18, one measurement). Instead, fill the cache
once on a login node, then install from it into `/dev/shm` in the job, without network:

```bash
# on a login node, once:
uv export --script myscript.py --no-hashes > myscript.txt   # the header's dependencies, pinned
uv sync --script myscript.py                                # fills the uv cache, runs nothing
# in the job script:
export UV_OFFLINE=1 UV_LINK_MODE=copy
V=/dev/shm/$SLURM_JOB_ID/venv
uv venv -q --python 3.13 "$V" && uv pip install -q -p "$V" -r myscript.txt
"$V/bin/python" myscript.py
```

Measured on `shared` CPU nodes (`-c 2`, 2026-11-19), for a script that imports numpy, scipy and
ase and does a few milliseconds of work. Seconds per run:

| Node | `/dev/shm` install | from `/dev/shm` | from a venv in `$HOME` | `uv run --script` |
|---|---|---|---|---|
| quiet | 6.8 | 2.9 | not measured | 17.2 |
| busy (load average 74) | 5.7 | 1.2, then 0.8 | 22.7, then 10.6 and 11.6 | 4.7 |

Rows are two test jobs, one run each per cell unless several are listed. The install column is
building the environment from the cache; the others are the whole run, imports included. The
environment takes 254 MB (6,200 files) in `/dev/shm`. A venv in `$HOME` is fine on a login node
and for Jupyter, but a job imports from it through DVS (below), the slowest route measured here.

- `/dev/shm` (and `/tmp`, also memory on compute nodes) uses the job's memory: a `shared`
  job gets about 1.9 GB per CPU (3.8 GB with `-c 2`). Large stacks (torch, CuPy, GPAW) run in
  the group container instead.
- It is local to each node and emptied after the job: a multi-node job installs on every node
  (`srun --ntasks-per-node=1 ...`).
- An environment used by many jobs can also go under `/global/common/software/<project>/venvs/`,
  which is fast for imports, but its 10 GB quota is shared by the whole group: ask first.

**Set `PYTHONSAFEPATH=1` in jobs whose working directory is in `$HOME` or on CFS.** Python
puts the script's directory (or the working directory) first on its import path, so every
import looks there first. Compute nodes reach `$HOME` and CFS through DVS, which serves each
file from a single gateway node: with many processes, nodes or concurrent jobs, these lookups
become the bottleneck (NERSC's *DVS* page). `export PYTHONSAFEPATH=1` in the job script (or
`python -P`, Python ≥ 3.11) removes that entry and nothing else; `PYTHONPATH` still works. This
holds inside the group container too when the job's working directory is a bind of `$HOME` or
CFS. Two cautions:
- A script that imports a module lying next to it then fails with `ModuleNotFoundError`: put
  that directory on `PYTHONPATH`, or install it as a package.
- Don't use `python -I` for this. It also ignores `PYTHONPATH` and the other `PYTHON*`
  variables, so a checkout put first on `PYTHONPATH` (one way to run a branch in the container)
  would silently not be used.

Because the cache (on `$SCRATCH`) and environments in `$HOME` are on different file
systems, uv prints *"Failed to hardlink files; falling back to full copy"*. This is
harmless. Silence it with `export UV_LINK_MODE=copy` in `~/.bashrc`.

To use an environment in Jupyter, see [page 8](08-jupyter.md).
