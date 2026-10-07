# 5. Python with uv

**First choice for GPU work and the big science stack (abTEM, GPAW, torch, CuPy, …):
the group container** ([page 6](06-containers.md)), where everything is already
installed and tested. Use uv for your own analysis code, small tools, and anything the
container doesn't have (abTEM from your own environment: [page 7](07-abtem.md#route-2-your-own-uv-environment)).

[uv](https://docs.astral.sh/uv/) installs Python itself and packages, much faster than
pip or conda. After the group setup ([page 2](02-shell-setup.md#2-group-environment))
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

Because the cache (on `$SCRATCH`) and environments in `$HOME` are on different file
systems, uv prints *"Failed to hardlink files; falling back to full copy"*. This is
harmless. Silence it with `export UV_LINK_MODE=copy` in `~/.bashrc`.

To use an environment in Jupyter, see [page 8](08-jupyter.md).
