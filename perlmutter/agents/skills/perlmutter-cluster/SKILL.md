---
name: perlmutter-cluster
description: Conventions and gotchas for running jobs and GUI/native tools on NERSC Perlmutter — NERSC's command guard for AI agents, podman-hpc container quirks, bind-mount asymmetry, CUDA/CuPy toolchain conflicts, Slurm mail/queue conventions (exclusive vs shared QOS, requesting a partial GPU node), interactive-first testing, Python on a login node, Pacific-time timestamps, HDF5 or uv file-locking errors (errno 524) on CFS or $HOME, where package data files (model checkpoints, potentials, GPAW data sets) are kept. Use when writing or debugging a Perlmutter sbatch/salloc script, running tests or benchmarks inside a Perlmutter container (the pytest, rootdir and package-shadowing traps are in idrobolab-container), diagnosing a CUDA/CuPy version mismatch there, setting up a native (non-container) tool in a shared Perlmutter environment, or when NERSC's filesystem-guard hook blocks a shell command an AI agent runs on a login node.
---

# NERSC Perlmutter conventions

The group's rules are in `perlmutter/agents/group.md` and its pages in `docs/perlmutter/`
(both in the idrobolab-env clone); this skill adds measured gotchas to them. Work inside the
group image is the `idrobolab-container` skill.

## Containers: podman-hpc, not Apptainer

Perlmutter's container runtime is **podman-hpc** — `podman-hpc pull <image>` to fetch a
published image (Delta's equivalent is `apptainer build docker://...`; don't assume the
same pull command works on both clusters).

- **Images are pulled by hand by the maintainer** (`group.md`, *Software*): commands reference
  the image by its full name (`$IDROBOLAB_IMAGE`, which is `ghcr.io/idrobolab/idrobolab:latest`;
  a bare `idrobolab:latest` can resolve to a different, older local image) and never
  include a `podman-hpc pull` step. If a run needs a newer image, say so and stop.
- **`/global/common/software/<project>/` is the project's base for installing software
  itself — Python packages, venvs, editable checkouts meant to be *run*, not scratch
  data.** It is mounted **read-only on compute nodes** (a `pip install`/`uv sync`/editable
  reinstall there has to happen from a login node, not from inside a job) and is tuned for
  the small-file, many-open/stat/read access pattern software installs and imports
  actually generate — unlike `$SCRATCH` (large sequential I/O) or `$HOME` (small quota,
  not for anything shared across a project). Put a project's installed packages and venvs
  here, not on `$CFS` or `$SCRATCH`, even though those are also project-shared.
- **A custom software directory is not visible inside the container at its own host path.**
  podman-hpc mounts nothing by default, so `$CFS`, `$SCRATCH` and `$HOME` are visible only
  where a `-v X:X` passes them (`docs/perlmutter/06-containers.md`); a project-specific
  directory (e.g. somewhere under `/global/common/software/<project>/...`) is only visible
  inside the container at wherever the image's recipe explicitly mounts it (conventionally
  `/opt/src/<package>`), and nowhere else. Always pass paths into or out of the container
  relative to that in-container mount point, not the host path.

## CUDA / CuPy toolchain

- **An `nvhpc` SDK CUDA install on `PATH` can silently conflict with a pip-installed
  `cupy-cudaXXx` built against a different CUDA minor version** — symptoms are
  `cuSOLVER`/`cuFFT` coming up unloadable or reporting a `None` version rather than an
  explicit mismatch error. Load a matching `cudatoolkit` module, or install the
  `nvidia-*-cuXX` pip wheels the CuPy build expects, before trusting any GPU numerics
  here — don't assume "a CUDA toolkit is on PATH" is sufficient.
- **CuPy ≥14 routes `cupy/complex.cuh` through CCCL, which requires C++17 for any
  `RawModule` kernel compiled against it** — a kernel that hardcodes `--std=c++14` raises
  an `NVRTCCompileException` under CUDA/CuPy 14 here, even though the identical kernel is
  silently fine on a ROCm/`amd-cupy` 13.5.1 build (whose `complex.cuh` skips CCCL
  entirely). A kernel meant to run on both CUDA and ROCm backends should not hardcode a
  C++ standard at all — track whatever CuPy's own bundled headers expect, since CuPy
  itself pins none.
- **`dask-cuda` under-declares its `cuda-bindings` dependency**, so a plain PyPI resolve
  can install a `dask-cuda` that fails at import (`cuda-core` needs `from cuda import
  bindings`, and the wheel providing that only resolves from NVIDIA's own package index).
  Resolve `dask-cuda` + `cuda-bindings` + the rest of the environment together, from
  `https://pypi.nvidia.com`, in one pass — a two-phase install (base env, then add
  `dask-cuda` after) can let a dependency solver silently downgrade an already-installed
  package to satisfy the late addition.

## Slurm and shell environment specifics

- **Every timestamp Perlmutter itself prints — `date`, `nvidia-smi`, job `.out` logs,
  `squeue`, file mtimes on its filesystems — is Pacific time (PT/PDT), and so is the clock
  of a session on a Perlmutter login node.** The offset to UTC is 7-8 hours depending on
  daylight saving, enough to put a Pacific evening on the next UTC date. Convert one side to
  UTC before reasoning about "before/after" or elapsed time against records kept in UTC.
- **Exception: Slurm's own error lines in a job's `.out` log are UTC**, in ISO format
  (`*** JOB <id> ON <node> CANCELLED AT 2026-09-28T20:06:18 DUE TO TIME LIMIT ***`), although
  `date` on the compute node and file mtimes are Pacific. Example: for a 30-minute debug job
  whose output files were written 12:37–12:47 PDT, the cancel line's 20:06 is 13:06 PDT. Convert
  before putting a Slurm line next to file times or the job's own printed times.
- **A job log that stops is not evidence of a hang: Python's stdout is block-buffered under
  Slurm and in containers.** Output goes to a file or pipe, not a terminal, so printed lines wait
  in a buffer until something flushes it, and a job killed at its time limit loses them.
  `multiprocessing` flushes stdout whenever it starts a process, so a log can end exactly at the
  last line before a dask or dask-cuda cluster starts while the job went on computing and writing
  files. Set `PYTHONUNBUFFERED=1` in the container environment, or call
  `sys.stdout.reconfigure(line_buffering=True)` in the script, and before concluding anything from
  where a log stops, compare the output files' mtimes with the job's start and end.
- **Compute nodes have no SSH key and no local mail-sending capability** — job-failure
  notification has to go through Slurm's own `--mail-type=FAIL --mail-user=...`, not a
  custom SMTP-based mailer script (which has no credentials available to it there
  anyway). Verified working via Slurm's own mail delivery.
- **Interactive shells here default to `noclobber`** — a plain `>` redirect to a file
  that already exists fails silently-ish (a shell error, not a crash); use `>|` to force
  the overwrite, or `set +o noclobber` if scripting around it repeatedly.
- **`-q interactive` is an exclusive QOS: it allocates, and charges for, a whole GPU node
  no matter how few GPUs are requested.** `--gpus N` only sets how many of the node's 4
  A100s are *visible* to the job. So `salloc -C gpu -q interactive --gpus 1 ...` bills a
  full node while exposing a single GPU. `regular`, `debug`, `preempt` and `premium` are
  exclusive in the same way. Use an exclusive QOS only when the job wants the whole node,
  and then request all of it (`--gpus 4`). The QOS table is in `docs/perlmutter/04-jobs.md`.
- **A partial-node job goes through a shared QOS and must state both its CPU and its GPU
  count explicitly**: `-q shared_interactive` for `salloc` (≤ 4 h) or `-q shared` for
  `sbatch` (≤ 48 h, e.g. periodic CI-style runs); the commands are in
  `docs/perlmutter/04-jobs.md`. Both are capped at half a node (1 or
  2 GPUs) and charge only the fraction used. Each GPU comes with 16 physical cores and
  64 GB RAM. Slurm's `-c` counts logical CPUs (2 hardware threads per core), so that is
  `-c 32` per GPU, which is NERSC's own 1-GPU shared example. For 2 GPUs, double the CPU
  count (`-c 64`) but give the GPU count with `--gpus=2`, **not** `--gpus-per-task=2`:
  `-n 1 -c 64 --gpus-per-task=2` is rejected at submission. The shared queue's
  cores-per-GPU check counts it as one GPU: `Logical queue
  gpu_shared_interactive_ss11 requires you to request 32.0 cores per GPU, job requested
  64 cores (adjusted for memory) for 1 GPUs`. The `--gpus=2` form was verified on
  2026-09-26 and matches what 2-GPU `sbatch -q shared` jobs use. Never leave the CPU
  count to Slurm's default in a shared job. *(Per NERSC's* Queue policies *and* Running
  jobs *pages, checked 2026-09-24.)*
- **`shared_interactive` allows 2 submitted jobs per user** (`MaxSubmitPU` = 2, read with
  `sacctmgr -n -P show qos shared_interactive format=name,maxsubmitpu,maxjobspu,maxwall` on
  2026-11-09; `shared` allows 5000). A third `salloc` fails at once with `salloc: error:
  QOSMaxSubmitJobPerUserLimit` ("Job violates accounting/QOS policy (job submit limit, ...)"),
  and every interactive job of the user counts, whichever session or terminal holds it.
  Before an `salloc`, list them: `squeue -u $USER -o '%i %q %j %T %M %l'`. A run that needs
  no watching goes to `sbatch -q shared` instead of waiting for a slot. Never cancel a job
  that this session did not start to make room.
- **`salloc` without a command opens the shell on the compute node** (confirmed 2026-10-06);
  `salloc <command>` runs the command on the login node, so a script started
  that way reaches the allocation only through `srun`. `exit` releases the allocation.
- **`srun` on a GPU (`podman-hpc run --gpu`, `--gpus`) needs an allocation**: from a login
  shell it does not run. Give the user the `salloc` line with every such `srun` command; the
  lines are in `docs/perlmutter/04-jobs.md`, with `<account>` the group's GPU account
  (`<project>_g`, `<project>` being `$NERSC_PROJECT`).
- **Declare `-L` (`--licenses`) for exactly the file systems the job touches**, and for no
  others; names and cases in `docs/perlmutter/04-jobs.md`, *File system licenses*.
- **Interactive first.** For any check short enough to want the answer immediately (a
  preflight, a single test file, a small correctness script — under about an hour), use
  `salloc` with `shared_interactive` and the explicit counts above (unless the check needs
  all 4 GPUs) and watch it, rather than `sbatch` and polling the queue; reserve `sbatch` for
  runs long enough that holding an interactive allocation open would waste it. Check
  `hostname` shows a compute node (`nid...`) before running anything heavy.

## NERSC's command guard for AI agents

On Perlmutter login nodes, `/etc/claude-code/managed-settings.json` (root-owned, above every user
and project setting, so it cannot be turned off) runs NERSC's `nersc_filesystem_guard.py` as a
`PreToolUse` hook before every Bash command an AI agent runs ("Checking filesystem traversal
scope"). It blocks broad directory scans (`find /`, `du`, `grep -r` over a broad root such as
`/global/cfs` or `/pscratch`). Claude Code's own Read, Grep and Glob tools are not checked. The
commands it checks, the roots it blocks and the measured decisions are in
`docs/perlmutter/reference/nersc-filesystem-guard.md` (idrobolab-env clone).

- **Scope is the agent's job, checked or not.** Keep every search, with any tool, to the directory
  the task needs. The hook misses some broad scans, so "allowed" does not mean harmless.
- **A command blocked for its directory is narrowed** to a literal path or `$VAR` below the root
  (`$PSCRATCH/<dir>`, a named project directory), never rewritten to slip past the hook through
  another tool, `cd`, `xargs` or a launcher. If the narrowed command is still blocked, report the
  hook's message to the user.
- **One false alarm:** with `grep -r`, the hook reads the pattern as a directory too, so a pattern
  holding `$`, `[`, `*`, `?` or `{` gets a bounded search blocked. Only when the same command with
  a plain pattern is allowed, attach the pattern to its option (`grep -rn --regexp='foo$' src/`)
  or search the same directory with the Grep tool or `rg`.
- Find software with `command -v`, `type -a` or `module spider`, not by scanning software trees.

## Software data files

Package-specific data files — ML-potential checkpoints (ORB, FAIRChem), LAMMPS potentials,
GPAW data sets, and the like — live in `/global/cfs/cdirs/<project>/software_data` (underscore),
the group's shared directory for them. Put such files there, not in `$HOME`, `$PSCRATCH`
(purged) or a project folder, and look there before downloading a copy. Compute nodes have no
outbound network, so a model that downloads on first use must already be there. Point a package
at it through its own variable (`ORB_CACHE_DIR`, `FAIRCHEM_CACHE_DIR`, `GPAW_SETUP_PATH`, ...).
A container sees it only through a bind mount, with `--group-add keep-groups` (the `<project>`
group owns it).

- `orb/`: the ORB v3 `*.ckpt` files in one flat directory (`ORB_CACHE_DIR` points here):
  `orb-v3-{conservative,direct}-{20,inf}-omat-20250404.ckpt`. `20` caps the graph at 20
  neighbours per atom, `inf` keeps every neighbour inside the cutoff.
- `fairchem/`: a Hugging Face hub cache of the UMA models (`CACHEDIR.TAG`, `.locks/`,
  `models--facebook--UMA/{blobs,refs,snapshots}`). The checkpoints are
  `models--facebook--UMA/snapshots/<revision>/checkpoints/*.pt`: `uma-m-1p1`, `uma-s-1p2p1` and
  `uma-s-1p2p1-ft-r2scan` when this was written. fairchem-core 2.22.0 (in the image) loads one by its file path:
  `pretrained_mlip.load_predict_unit(<path>, device="cuda")`, then `FAIRChemCalculator(unit, task_name="omat")`.

## Python outside the container

`uv` is installed on Perlmutter, with managed interpreters under the project's software
directory (the `UV_PYTHON_INSTALL_DIR` in `/global/common/software/<project>/uv/pythons/`).
Whenever "just a Python" is needed on a login node — a stdlib-only helper, a one-off script,
a step that must run outside the container — use uv's interpreter (`uv run --no-project
python ...`, or `uv run --script` for a PEP 723 script), not the system `python3`: the login
node's `python3` is old (no `-P`, may predate `dict[str, str]` syntax). Keep uv's cache and
managed Pythons, and any venv, pip or conda cache, off `$HOME` (file-count limits and
filesystem locking break them there). Container runs are unaffected: inside the image the
venv's own `python` is the right one.

**Always set `UV_CACHE_DIR` to a `$PSCRATCH` path before running uv on a compute node.** The
default cache under `$HOME/.cache/uv` fails with `Could not acquire lock ... Unknown error 524`
(the home filesystem does not support the lock uv takes), so every `uv run`/`uvx` aborts before
doing anything. `perlmutter/env.sh` in the idrobolab-env clone sets it (`$SCRATCH/uv-cache`,
guarded, pre-set value respected); a shell that has not sourced that file needs
`export UV_CACHE_DIR=$PSCRATCH/uv-cache` by hand.

**HDF5 files on CFS or `$HOME` fail to open from a compute node with `unable to lock file,
errno = 524`.** HDF5 (h5py included) takes a `flock` on every open, which those mounts do not
support. Set `HDF5_USE_FILE_LOCKING=FALSE` in the process that opens them (for a command run
through `ssh` to the node, inside the remote command: an `export` on the login node does not
cross). With the lock off, nothing guards one file against two writers.


## Native (non-container) tools in a shared environment

For a native-launcher tool (a Qt-based GUI with an embedded Python, say) in a shared Perlmutter
software environment, the libexpat/`pyexpat` crash and its `python-build-standalone` or
`LD_PRELOAD` remedies are in `docs/perlmutter/reference/nionswift-perlmutter-thinlinc.md`
(idrobolab-env clone). Two rules hold for any shared venv:

- **A venv's own Python must resolve to a path visible to every intended user**, not
  somewhere under one person's `$HOME` — set the venv/interpreter install directory to a
  shared, group- or project-readable location explicitly (e.g. `uv`'s own
  `UV_PYTHON_INSTALL_DIR`), or only the person who created it can actually run it.
- **Don't seed a shared venv from a cluster-provided Python module as its base
  interpreter** — module upgrades can silently replace what that base pointed to,
  breaking every venv built from it after the fact. Seed from an environment under one's
  own control instead (a maintained conda base, or a pinned `python-build-standalone`
  release).
