# Slurm submission files for the project containers on Perlmutter

Template job scripts per node type and QOS. All take the payload as
arguments (`sbatch <script>.sbatch my_script.py [args...]`; the `ptyrad_*` ones take a
ptyrad params file, `sbatch <script>.sbatch params.yaml [options...]`), locate the image
via `$IMAGE` (default `$IDROBOLAB_IMAGE` from `env.sh`, a full reference to
`ghcr.io/idrobolab/idrobolab:latest`, else `idrobolab`; overridable at submit time with
`IMAGE=... sbatch ...`). A bare name resolves to
`ghcr.io/${IMAGE_OWNER:-idrobolab}/<name>:${TAG:-latest}`, so `TAG` and
`IMAGE_OWNER` take effect only together with a bare name (`IMAGE=idrobolab TAG=v2`);
a value containing `/` is used verbatim, which is how any other image is given.
The templates mount `$SCRATCH`, `$CFS`, and `$HOME` when present. The exceptions
are `abtem_uv_gpu_shared.sbatch` and `abtem_uv_gpu_node.sbatch`, which run abTEM
from a uv environment on the host (`~/venvs/abtem`) and use no container.

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

| Script | Constraint / QOS | Resources | Cost per wallclock hour | Licenses | Intended use |
|---|---|---|---|---|---|
| `gpaw_cpu_singlenode.sbatch` | `cpu` / `regular` | 1 node, 128 ranks, 512 GB | 1 CPU node-hr | `scratch,cfs` | GPAW MPI on one node |
| `gpaw_cpu_multinode.sbatch` | `cpu` / `regular` | 4 nodes × 128 ranks | 4 CPU node-hr | `scratch,cfs` | Large GPAW SCF |
| `gpu_1gpu_shared.sbatch` | `gpu` / `shared` | 1 A100, 32 logical cores | **0.25** GPU node-hr | `scratch,cfs` | **Default for GPU work** — dev, abTEM, orb, torch |
| `gpu_2gpu_shared.sbatch` | `gpu` / `shared` | 2 A100, 64 logical cores | **0.5** GPU node-hr | `scratch,cfs` | One process, or one abTEM calculation over 2 GPUs (dask-cuda) |
| `abtem_uv_gpu_shared.sbatch` | `gpu` / `shared` | 1 or 2 A100 (two `#SBATCH` lines), 32 or 64 logical cores | **0.25** / **0.5** GPU node-hr | none (set by you) | abTEM from your own uv environment (`~/venvs/abtem`), no container |
| `abtem_uv_gpu_node.sbatch` | `gpu` / `regular` | 1 node, 4 tasks × 1 A100 | 1 GPU node-hr | `scratch` | Four independent single-GPU abTEM runs (a sweep) from `~/venvs/abtem` |
| `gpu_4gpu_node.sbatch` | `gpu` / `regular` | 1 node, 4×A100 40 GB, 256 GB | 1 GPU node-hr | `scratch,cfs` | One process driving 4 GPUs |
| `ptyrad_1gpu_shared.sbatch` | `gpu` / `shared` | 1 A100, 32 logical cores | **0.25** GPU node-hr | `scratch,cfs` | **Default for ptyrad**: `ptyrad run <params.yaml>` on one GPU |
| `ptyrad_2gpu_shared.sbatch` | `gpu` / `shared` | 2 A100, 64 logical cores | **0.5** GPU node-hr | `scratch,cfs` | One ptyrad reconstruction over 2 GPUs (`accelerate launch`), or with `FIRST_SEED=<n>` two independent ones with seeds n, n+1 |
| `ptyrad_4gpu_node.sbatch` | `gpu` / `regular` | 1 node, 4×A100 40 GB, 256 GB | 1 GPU node-hr | `scratch,cfs` | One ptyrad reconstruction over 4 GPUs (`accelerate launch`), or with `FIRST_SEED=<n>` four independent ones with seeds n…n+3 |
| `gpu_4gpu_hbm80g.sbatch` | `gpu&hbm80g` / `regular` | 1 node, 4×A100 **80 GB** | 1 GPU node-hr | `scratch,cfs` | complex128 EMCD, exact-S₂, big S-matrix budgets |
| `gpu_multinode_mpi.sbatch` | `gpu` / `regular` | 2 nodes × 4 ranks, 1 GPU/rank | 2 GPU node-hr | `scratch,cfs` | GPU-parallel GPAW, distributed torch |
| `debug_gpu.sbatch` | `gpu` / `debug` | 1 GPU, ≤30 min | 1 GPU node-hr | `scratch,cfs` | Smoke tests before a long run |
| `interactive_gpu.sh` | `gpu` / `interactive` | 1 node, ≤4 h | 1 GPU node-hr | `scratch,cfs` | Shell in the container (helper, not sbatch) |
| `interactive_gpu_shared.sh` | `gpu` / `shared_interactive` | 1 or 2 A100 (`GPUS=`), 32 or 64 logical cores, ≤4 h | **0.25** / **0.5** GPU node-hr | `scratch,cfs` | Shell in the container (helper, not sbatch) |
| `interactive_jupyter.sh` | `gpu` / `shared_interactive` | 1 A100, 32 logical cores, 2 h | **0.25** GPU node-hr | `scratch,cfs` | JupyterLab in the container + the `ssh -L` line to reach it (helper, not sbatch) |

**Licenses** are the NERSC file-system licenses each script declares; choosing them: [page 4](../../docs/perlmutter/04-jobs.md#file-system-licenses).

Which of these to use for abTEM, in the container or from your own uv environment, is
the subject of [page 7](../../docs/perlmutter/07-abtem.md).

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

**`shared` is a batch QOS; `shared_interactive` is its interactive twin.** Both
give you a fraction of a node charged by the fraction held, but a session
submitted to `shared` waits behind regular batch work — which is exactly what
makes an interactive notebook or GUI unusable. Use `shared` from `sbatch`,
`shared_interactive` from `salloc`. `interactive_jupyter.sh` and the nionswift
launcher both default to `shared_interactive`; its own limits are not tabulated
here because they have not been checked against `sacctmgr` on-cluster.

When an allocation does not start, `squeue --me -o "%i %q %P %T %r"` shows the
QOS it landed in and the pending reason, and `scontrol show job <id>` gives the
full picture. A session that ends up in an unexpected QOS is worth stopping
rather than waiting out.

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
  `LD_LIBRARY_PATH` surgery. Compare [`delta/jobs/gpaw_cpu_multinode.sbatch`](../../delta/jobs/gpaw_cpu_multinode.sbatch)
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
../helpers/update-image.sh idrobolab # pulls into the shared CFS store
                                     # and fixes its permissions
podman-hpc images --digests          # record the digest with your results
# (a locally BUILT image also needs `podman-hpc migrate <tag>` to be visible
#  on compute nodes; pulled images are migrated automatically)

sbatch debug_gpu.sbatch              # runs the built-in smoke test:
                                     #   GPUs visible, abtem/cupy/torch/gpaw versions,
                                     #   a small abTEM multislice on the GPU,
                                     #   4-rank Cray-MPICH world
```

Interactive equivalent (a shell in the container on the compute node):

```bash
./interactive_gpu_shared.sh          # 1 A100 slice, 1 h; GPUS=2 for two
./interactive_gpu.sh                 # a whole node, 4 A100
```

Notebook in the browser on your laptop:

```bash
./interactive_jupyter.sh              # 1 A100 slice, shared_interactive, 2 h — 0.25 node-hr/h
QOS=interactive GPUS=4 ./interactive_jupyter.sh    # whole node, 4x the charge
# paste the ssh -L line it prints on your laptop, open the URL with its host
# replaced by localhost, token unchanged
```

Full runbook for both routes — hub kernels and self-allocated sessions —
with knobs and troubleshooting: [jupyter.md](../../docs/perlmutter/reference/jupyter.md).

The container needs `-p <port>:<port>` for the port to exist on the node —
binding `0.0.0.0` inside the container is not enough, and `/proc/net/dev`
inside the container looks like host networking but is not. See
docs/perlmutter/reference/podman-hpc.md, "Networking".

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
- **Never pass `--mem` with `--gpus` on the `shared` QOS.** Slurm derives a
  core count from `--mem` as well as from `--cpus-per-task`, takes the larger,
  and the GPU shared queue requires *exactly* 32 logical cores per GPU:

  ```
  salloc: error: Logical queue gpu_shared_ss11 requires you to request 32.0
  cores per GPU, job requested 38 cores (adjusted for memory) for 1 GPUs
  ```

  64 GB works out to 38 cores at the node's ~1.7 GB per logical core, so
  spelling out the memory share is what breaks the request. Ask for
  `--cpus-per-task=$((32 * gpus))` and nothing else; the slice arrives with
  its proportional memory (~55 GB per GPU) regardless. `sbatch --test-only`
  checks a template against the queue rules without charging anything.
- **`salloc <command>` runs the command on the LOGIN node.** Only `srun`
  steps land on the allocated node. `salloc` with *no* command is the case
  that drops you onto a compute node; passing a command overrides that, and
  the failure is silent — the work runs on a shared login node with no GPU
  while the allocation sits idle and is charged. The giveaway is a hostname
  reading `loginNN` right after Slurm said `Nodes nidNNNNNN are ready`. Both
  interactive helpers wrap the payload in `srun` for this reason, and take
  the node name for the tunnel from `$SLURM_NODELIST` rather than `hostname`.
- **`$SCRATCH` (`/pscratch/sd/<first-letter>/<user>`) is purged**: any file
  not *accessed* in 8 weeks is deleted. Campaign results belong on `$CFS`
  (`/global/cfs/cdirs/<project>`), not scratch.
- **Never name a working directory (or output dir) `gpaw`.** The dev packages
  are editable installs, so a `gpaw/` subdirectory in the CWD shadows the
  real package through the namespace-package finder and you get
  `ImportError: cannot import name 'GPAW_NO_C_EXTENSION' from 'gpaw'`. Same
  trap for `gpaw_weaver`, `abtem`. Branch checkouts belong at
  `$SCRATCH/code/gpaw`, mounted onto `/opt/src/gpaw`.
- **For one-liner `python -c` checks, use `python -P`** (drops CWD from
  `sys.path`). Do *not* add `-P` to `python src/script.py` runs — it also
  drops the script's own directory and breaks sibling imports.
- **The `&` in `-C gpu&hbm80g`** is a Slurm operator. Unquoted is fine inside
  an `#SBATCH` line; on a command line it must be quoted or the shell
  backgrounds the job.
- **Always set `--time`.** The default is short and jobs die without warning.

## Testing status

One row per template or script; the second column is what the repository records about
running it on Perlmutter: a job ID and date where the repo has one, "run, not recorded"
where it only says the script was run, otherwise "not yet run". The group should test
every template systematically (short time limit, e.g. `sbatch -t 00:10:00`; note the job
ID, date, image digest and result in the PR) and update this table.

| Template / script | Recorded on Perlmutter |
|---|---|
| `debug_gpu.sbatch` | not yet run (the 2026-08-19 jobs <jobid> and <jobid> were `--wrap=true` tests of the account mapping) |
| `gpu_1gpu_shared.sbatch` | not yet run (its `--mem` removal of 2026-08-27 is recorded as "not yet run on-cluster") |
| `gpu_2gpu_shared.sbatch` | not yet run |
| `gpu_4gpu_node.sbatch` | not yet run |
| `gpu_4gpu_hbm80g.sbatch` | not yet run |
| `gpu_multinode_mpi.sbatch` | not yet run (confirm its GPU-binding probe first) |
| `gpaw_cpu_singlenode.sbatch` | not yet run |
| `gpaw_cpu_multinode.sbatch` | not yet run |
| `abtem_uv_gpu_shared.sbatch` | not yet run |
| `abtem_uv_gpu_node.sbatch` | not yet run |
| `ptyrad_1gpu_shared.sbatch`, `ptyrad_2gpu_shared.sbatch`, `ptyrad_4gpu_node.sbatch` | not yet run as jobs; the `ptyrad run` and 2-GPU `accelerate launch` commands were run by hand in an interactive container on 2 A100s (2026-10-26, ptyrad 1.0.0); the `FIRST_SEED` mode was tested only off-cluster, with a stub `ptyrad` |
| `examples/abtem/abtem_gpu_example.py` | not yet run on Perlmutter (only `--device cpu`, on a workstation, 2026-10-06) |
| `interactive_gpu.sh` | not yet run since its `srun` fix of 2026-08-27 |
| `interactive_gpu_shared.sh` | not yet run |
| `interactive_jupyter.sh` | run 2026-08-27 on nid001012, no job ID recorded (commit 4322e26) |
| `../verification/multigpu_abtem/benchmark_haadf_auto.sbatch` | job <jobid>, 2026-08-19, 4 A100: scaling at <efficiency> and invariant image (log in that folder) |
| `../verification/multigpu_abtem/multigpu_verify.sbatch`, `benchmark_haadf.sbatch` | not yet run |

Job <jobid> (2026-08-19, 4 A100) was a real GPU run, and a multi-GPU run without the
`__main__` guard failed that day (see Gotchas, commit 46938b2); the repo does not say
which template either used, so the rows above stay "not yet run".
