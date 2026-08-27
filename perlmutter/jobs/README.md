# Slurm submission files for the project containers on Perlmutter

Template job scripts per node type and QOS. All take the payload as
arguments (`sbatch <script>.sbatch my_script.py [args...]`), locate the image
via `$IMAGE` (default `idrobolab`; a bare name resolves against
`ghcr.io/<username>/`, a value containing `/` is used verbatim — overridable at
submit time with `IMAGE=... sbatch ...`), and mount `$SCRATCH`, `$CFS`, and
`$HOME` when present.

The `--account` lines are set to **<project>** (CPU templates) and **<project>_g** (GPU
templates); `sbatch -A <other>` overrides per submission.

**On the `_g` suffix — resolved, and it does not matter.** Both accounts exist,
and Slurm **remaps a GPU job to the `_g` pool automatically**. Verified on
Perlmutter 2026-08-19 by submitting with the plain account and reading back what
was recorded:

```
$ sacctmgr -nP show assoc user=$USER format=account | sort -u
<project>
<project>_g

$ sbatch -A <project>   -C gpu -q debug -N1 -t1 --wrap=true     # no suffix
$ sbatch -A <project>_g -C gpu -q debug -N1 -t1 --wrap=true     # suffix
$ sacct -j <jobid>,<jobid> -o JobID,Account
JobID           Account
<jobid>        <project>_g          <- submitted as <project>
<jobid>.ba+    <project>_g
<jobid>        <project>_g          <- submitted as <project>_g
<jobid>.ba+    <project>_g
```

Both arms land in `<project>_g`, on every step. A real GPU run behaves the same:
job <jobid>, submitted `-A <project>`, recorded `<project>_g` alongside
`gres/gpu:a100=4`. So the GPU allocation is what gets charged regardless of
which name you pass. That is why NERSC's two doc
pages look contradictory and are both right: the policy page's "no suffix
needed" describes the submission (true — the filter fixes it up), and the
running-jobs page's "the one without the trailing `_g`" describes the accounts
(also true — the suffixed one exists and is where GPU work lands).

The GPU templates still say `<project>_g` because it names the pool the job will be
charged to, which is worth stating outright. `-A <project>` works identically.

To find your own accounts on another project, use `-P`: `sacctmgr` truncates
columns by default, which is exactly how a wrong account name goes unnoticed.

```bash
sacctmgr -nP show assoc user=$USER format=account | sort -u
```

## Script ↔ resource matrix

| Script | Constraint / QOS | Resources | Cost per wallclock hour | Intended use |
|---|---|---|---|---|
| `gpaw_cpu_singlenode.sbatch` | `cpu` / `regular` | 1 node, 128 ranks, 512 GB | 1 CPU node-hr | GPAW MPI on one node |
| `gpaw_cpu_multinode.sbatch` | `cpu` / `regular` | 4 nodes × 128 ranks | 4 CPU node-hr | Large GPAW SCF |
| `gpu_1gpu_shared.sbatch` | `gpu` / `shared` | 1 A100, 16 cores, 64 GB | **0.25** GPU node-hr | **Default for GPU work** — dev, abTEM, orb, torch |
| `gpu_4gpu_node.sbatch` | `gpu` / `regular` | 1 node, 4×A100 40 GB, 256 GB | 1 GPU node-hr | One process driving 4 GPUs |
| `gpu_4gpu_hbm80g.sbatch` | `gpu&hbm80g` / `regular` | 1 node, 4×A100 **80 GB** | 1 GPU node-hr | complex128 EMCD, exact-S₂, big S-matrix budgets |
| `gpu_multinode_mpi.sbatch` | `gpu` / `regular` | 2 nodes × 4 ranks, 1 GPU/rank | 2 GPU node-hr | GPU-parallel GPAW, distributed torch |
| `debug_gpu.sbatch` | `gpu` / `debug` | 1 GPU, ≤30 min | 1 GPU node-hr | Smoke tests before a long run |
| `interactive_gpu.sh` | `gpu` / `interactive` | 1 node, ≤4 h | 1 GPU node-hr | Shell in the container (helper, not sbatch) |
| `interactive_jupyter.sh` | `gpu` / `shared` | 1 A100, 16 cores, 64 GB, 2 h | **0.25** GPU node-hr | JupyterLab in the container + the `ssh -L` line to reach it (helper, not sbatch) |

## Node hardware

| | CPU node | GPU node |
|---|---|---|
| Count | 3,072 | 1,536 (40 GB) + 256 (80 GB) |
| CPU | 2× AMD EPYC 7763 (Milan) | 1× AMD EPYC 7763 (Milan) |
| Cores | 128 physical / 256 logical, 2 sockets, NPS=4 | 64 physical / 128 logical |
| Memory | 512 GB DDR4 | 256 GB DDR4 |
| GPUs | — | 4× A100, 40 GB HBM2 (1555 GB/s) or 80 GB HBM2e (2039 GB/s), NVLink3 |
| NIC | 1× Slingshot-11 | 4× Slingshot-11 |

`--cpus-per-task` follows NERSC's rule of thumb — logical CPUs per task =
`2 × ⌊physical_cores / tasks_per_node⌋`, i.e. `2 × ⌊128/n⌋` on CPU nodes and
`2 × ⌊64/n⌋` on GPU nodes. That is where `-c 2` (128 ranks/CPU node) and
`-c 32` (4 ranks/GPU node) come from.

## QOS limits and charging

Charge = `walltime_hours × nodes × QOS_factor × charge_factor`, and
Perlmutter's charge factor is **1.0** for both node types.

| QOS | Max nodes | Max time | Submit/run limit | QOS factor |
|---|---|---|---|---|
| `regular` | unlimited | 48 h | 5000 / — | 1.0 (0.75 for GPU jobs ≥128 nodes) |
| `interactive` | 4 | 4 h | 2 / 2 | 1.0 |
| `debug` | 8 | 30 min | 5 / 2 | 1.0 |
| `shared` | 0.5 | 48 h | 5000 / — | prorated by fraction of node |
| `preempt` | 128 | 48 h | 5000 / — | 0.25 GPU, 0.5 CPU (min 2 h guaranteed) |
| `overrun` | unlimited | 48 h | 5000 / — | 0 (only when out of allocation) |
| `jupyter` | 4 | 6 h | 1 / 1 | 1.0 |

**Use `shared` for 1–2 GPU jobs.** NERSC policy asks for it, and it is 4×
cheaper: a 1-GPU shared job gets 16 physical cores + 64 GB and is charged
0.25 node-hours per hour; 2 GPUs gets 32 cores + 128 GB at 0.5.

## How MPI is launched (important — differs from Delta)

On Perlmutter the container runtime is **podman-hpc**, and MPI integration is
a supported first-class feature rather than something to be hand-wired:

- `srun` launches **one container per rank**, and `podman-hpc run --mpi`
  bind-mounts the host Cray MPICH over the container's MPICH at runtime.
  Both provide `libmpi.so.12` (the image builds MPICH 4.3.2 from source with
  shared libs precisely for this), so the ranks link against Cray's
  Slingshot-optimised build and form one `MPI_COMM_WORLD`.
- This means **none of Delta's hybrid library-injection machinery is needed
  here** — no `APPTAINER_CONTAINLIBS`, no manual `/opt/cray` binds, no
  `LD_LIBRARY_PATH` surgery. Compare `delta/jobs/gpaw_cpu_multinode.sbatch`
  to see what that saves.
- Single-node and multi-node use the **same** mechanism, so unlike on Delta
  there is no riskier multi-node code path.
- **Fallback**: drop `--mpi` and the container's own MPICH runs over TCP.
  Correct results, lower bandwidth — fine for modest rank counts.
- For NCCL collectives across nodes (torch DDP), add `--nccl-cu12` to load
  NERSC's Slingshot-tuned plugin (`--nccl-cu13` if the image moves to CUDA 13).
- If multi-node MPI init fails with a misleading `No space left on device`,
  add `--network=no_vni` (already set in the multi-node templates).

## First-run checklist

```bash
# on a Perlmutter login node, once:
../update-image.sh idrobolab         # or another image — pulls into the shared
                                     # CFS store and fixes its permissions
podman-hpc images --digests          # record the digest with your results
# (a locally BUILT image also needs `podman-hpc migrate <tag>` to be visible
#  on compute nodes; pulled images are migrated automatically)

sbatch debug_gpu.sbatch              # runs the built-in smoke test:
                                     #   imports + versions, torch sees the A100,
                                     #   4-rank Cray-MPICH world, extra-module pytest
```

Interactive equivalent:

```bash
salloc -A <project>_g -C gpu -q interactive -N 1 --gpus-per-node=4 -t 01:00:00
podman-hpc run --rm -it --gpu -v $SCRATCH:$SCRATCH ghcr.io/<username>/otherimage:latest /bin/bash
# or just: ./interactive_gpu.sh
```

Notebook in the browser on your laptop:

```bash
./interactive_jupyter.sh              # 1 A100 on a shared node, 2 h — 0.25 node-hr/h
QOS=interactive GPUS=4 ./interactive_jupyter.sh    # whole node, starts sooner, 4x the charge
# paste the ssh -L line it prints on your laptop, open the URL with its host
# replaced by localhost, token unchanged
```

No `-p` is needed on the container: podman-hpc uses the host network stack, so
`--ip=0.0.0.0` binds the port on the node itself. See ../podman-hpc.md,
"Networking".

## Gotchas

- **Your script needs `if __name__ == "__main__":` if it uses multiple GPUs.**
  dask-cuda starts workers with multiprocessing's **spawn** method (it must —
  `fork` is unsafe once a CUDA context exists), and spawn *re-imports the main
  module* in every child. A script that does its work at module level therefore
  re-runs that work in each worker, which tries to start a cluster of its own:

  ```
  RuntimeError:
      An attempt has been made to start a new process before the
      current process has finished its bootstrapping phase.
  ```

  The giveaway is your own output repeating N times before the traceback, plus
  `Port 8787 is already in use. Perhaps you already have a cluster running?`.
  Nothing about the container or Slurm is wrong. Move everything that *does*
  something under the guard:

  ```python
  def main():
      atoms = read("structure.cif")      # was at module level
      ...                                # everything else too
  if __name__ == "__main__":
      main()
  ```

  Definitions (functions, classes, constants) can stay at module level — they
  are what the child needs to import. The payloads in
  `../verification/multigpu_abtem/` are written this way if you want a template.

- **`GPAW_MPI_BACKEND=cgpaw` is mandatory under `srun`.** The image ships
  GPAW 26.7.1b1, and since 26.7.0 GPAW aborts at import with *"GPAW appears
  to be running inside MPI launcher, but MPI parallelism is disabled"* when
  an MPI launcher starts plain `python`. Every MPI template here exports it;
  add it to any new one. (`gpaw python` avoids the flag but swallows script
  arguments, which is why the projects use plain `python`.)
- **podman-hpc mounts nothing by default.** Apptainer on Delta inherits
  `$HOME` and `$PWD` for free; podman-hpc does not. Every path the job reads
  or writes — inputs, outputs, PAW setups, branch checkouts — needs an
  explicit `-v host:container`, and the templates set `--workdir` for the same
  reason.
- **CFS has two names, and the container only knows the one you mount.**
  `/global/cfs/projectdirs/<project>` is a symlink to
  `/global/cfs/cdirs/<project>`; your login shell accepts either, `$CFS` is the
  `cdirs` spelling, and submitting from the other used to fail before the
  payload ever started:

  ```
  Error: workdir "/global/cfs/projectdirs/<project>/..." does not exist on container <id>
  ```

  The templates' `add_mount` now resolves each path with `pwd -P` and mounts
  every CFS tree under **both** names — `/global/cfs/cdirs/<project>` and
  `/global/cfs/projectdirs/<project>`, each mounted from its own name so the
  container mirrors the cluster's own layout. Either spelling works, as the
  submit directory and in paths handed to the payload; `--workdir` itself is
  set to the canonical `cdirs` path, which is the one guaranteed to be mounted.
  Keep that helper if you copy a
  template, and add campaign directories with `add_mount <dir>`: it also skips
  a path already covered by a broader mount, which podman would otherwise
  reject as a duplicate destination. Append to `$MOUNTS` by hand only when the
  host and container paths differ, as the commented-out branch-checkout
  overrides do.
- **`$SCRATCH` (`/pscratch/sd/<first-letter>/<user>`) is purged**: any file
  not *accessed* in 8 weeks is deleted. Campaign results belong on `$CFS`
  (`/global/cfs/cdirs/<project>`), not scratch.
- **Never name a working directory (or output dir) `gpaw`.** The dev packages
  are editable installs, so a `gpaw/` subdirectory in the CWD shadows the
  real package through the namespace-package finder and you get
  `ImportError: cannot import name 'GPAW_NO_C_EXTENSION' from 'gpaw'`. Same
  trap for `otherimage`, `gpaw_weaver`, `pyslice`. Branch checkouts belong at
  `$SCRATCH/code/gpaw`, mounted onto `/opt/src/gpaw`.
- **For one-liner `python -c` checks, use `python -P`** (drops CWD from
  `sys.path`). Do *not* add `-P` to `python src/script.py` runs — it also
  drops the script's own directory and breaks sibling imports.
- **The `&` in `-C gpu&hbm80g`** is a Slurm operator. Unquoted is fine inside
  an `#SBATCH` line; on a command line it must be quoted or the shell
  backgrounds the job.
- **Always set `--time`.** The default is short and jobs die without warning.

## Status

These templates follow the current NERSC documentation for podman-hpc, QOS
policy, and Perlmutter affinity, but **none has been run yet** — the image
itself is still the untested Dockerfile translation of the verified Delta
build (see `../podman-hpc.md`). Treat the first run of each as a test:
start with `debug_gpu.sbatch`, and confirm the GPU-binding probe in
`gpu_multinode_mpi.sbatch` before trusting a long multi-node run.
