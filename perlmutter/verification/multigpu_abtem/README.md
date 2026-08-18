# abTEM multi-GPU verification (Perlmutter)

Confirms that abTEM actually distributes a GPU simulation across **every GPU on a
node**, using the multi-GPU support on the abTEM `multi-gpu-support` branch (lazy
GPU computes routed through a `dask_cuda` cluster, one worker process per GPU).

Same checks, same Python, same container as the Delta suite — only the launchers
differ, because Perlmutter runs **podman-hpc** instead of Apptainer.

| File | Purpose |
|---|---|
| `setup_env.sh` | Preflight (no venv): confirms the branch abTEM + the container's dask-cuda import together via `PYTHONPATH`. Login node is fine. |
| `multigpu_verify.sbatch` | Slurm submission for the verification (`-C gpu`, 1 node, 4× A100). |
| `benchmark_haadf.sbatch` | Slurm submission for the HAADF benchmark — **explicit** `LocalCUDACluster` path. |
| `benchmark_haadf_auto.sbatch` | Slurm submission for the benchmark via the **automatic** path (`config['dask.multi-gpu']`). |
| `../../../shared/verification/multigpu_abtem/verify_multigpu.py` | The verification payload — environment report + cluster/coverage/distribution checks. |
| `../../../shared/verification/multigpu_abtem/benchmark_haadf.py` | Frozen-phonon HAADF benchmark: sweeps 1/2/4 GPUs, reports scaling, checks the image is invariant to GPU count. Explicit cluster. |
| `../../../shared/verification/multigpu_abtem/benchmark_haadf_auto.py` | Same benchmark through abTEM's automatic cluster init; sweeps counts as subprocesses. |

## The payloads are shared with Delta — on purpose

The `.py` files live in `shared/verification/multigpu_abtem/`, **not** here. Both
clusters run byte-identical Python from the same container image, so a number
measured on Perlmutter's A100s is directly comparable with one measured on
Delta's, and a fix to a check lands on both at once. Only the launchers (`.sbatch`,
`setup_env.sh`) are per-cluster, and they resolve the payloads relative to
themselves:

```bash
PAYLOAD_DIR=${PAYLOAD_DIR:-$HERE/../../../shared/verification/multigpu_abtem}
```

`perlmutter/verification/multigpu_abtem/` and `delta/verification/multigpu_abtem/`
sit at the same depth, so the same `../../../` works in both. Override
`PAYLOAD_DIR` if you keep the payloads somewhere else. Note that `sbatch` executes
a **spool copy** of the script, so `BASH_SOURCE` points into the spool directory
where the payload is absent — the launchers use `$SLURM_SUBMIT_DIR` and only fall
back to the script's own directory for `bash` runs. **Submit from this
directory.**

A sparse checkout works as long as `shared/` is in the set:

```bash
git sparse-checkout set shared perlmutter
```

The only thing that set does not bring is the Delta README this file links to
once (for the dask/dask-cuda analysis); add `delta` to the set if you want it
locally.

## podman-hpc, not Apptainer — nothing is mounted by default

This is the single biggest difference from the Delta launchers, and the one most
likely to bite.

- The image is an **OCI image**, not a `.sif`: `ghcr.io/<username>/otherimage:latest`,
  overridable with `IMAGE=...`. Pull/refresh it into the project's shared CFS
  store with `../../update-image.sh otherimage` — **the argument is not
  optional**, the script defaults to `idrobolab` — on a login node only, since
  compute nodes have no route to ghcr.io. Then `source ../../env.sh` so
  `PODMANHPC_ADDITIONAL_STORES` points at the read-only `/dvs_ro` mirror of that
  store.
- **Apptainer inherits `$HOME` and `$PWD`; podman-hpc inherits nothing.** Every
  path the job touches needs an explicit `-v host:container`: the payload
  directory, the abTEM checkout, `$SCRATCH`, `$CFS`, `$HOME`, and the output
  directory. A missing mount does not warn — the path simply is not there, and
  you get a `FileNotFoundError` (best case) or a silently wrong import (worst
  case, see below).
- GPUs need the **`--gpu`** flag: `podman-hpc run --rm --gpu ...`.
- Environment goes in with **`-e VAR=value`**. There is no `APPTAINERENV_`
  mechanism, and the container does not inherit the submitting shell's
  environment.
- The container's working directory is not yours either, so every launcher sets
  `--workdir` explicitly. `multigpu_verify.sbatch` and `benchmark_haadf_auto.sbatch`
  point it at the submit directory; `benchmark_haadf.sbatch` points it at `$OUT`
  on `$SCRATCH`, because dask-cuda workers put their spill directory in the CWD
  and the submit directory is usually the `$HOME` checkout with its 40 GB quota.

## How the branch abTEM is injected (no venv)

The container carries its own abTEM, installed **editable** from a checkout
staged into the build context (`shared/containers/otherimage/Dockerfile`:
`COPY src/abTEM /opt/src/abTEM` + `pip install -e /opt/src/abTEM`). Do **not**
identify it by version: the Delta README called it 1.0.9, while the
Dockerfile in this repo stages an abTEM main **1.1.0** checkout, so which abTEM a
given image holds — and whether it already carries multi-GPU code — depends on
what was staged when that image was built. Check `podman-hpc images --digests`
and section 0's printed path, not a version you expect.

Upgrading it per job is not the answer. "The image is read-only" is a Delta (SIF)
argument that does **not** hold under podman: every `podman-hpc run` gets a
writable overlay, so a `pip install` inside one appears to work and is then
thrown away when the container exits. A nested
`python -m venv --system-site-packages` does not work here either: the
container's Python is itself a venv, and `--system-site-packages` inherits only
the *base* interpreter's packages, not the container venv's — so the venv cannot
see dask-cuda/cupy. Instead the branch checkout goes on **`PYTHONPATH`**,
shadowing the container's abTEM while dask-cuda/cupy/dask still come from the
container. abTEM is pure Python with a committed `abtem/_version.py`, so there is
no build or install step.

`PYTHONPATH` does shadow an *editable* install — the one case where that is
worth verifying rather than assuming, since an editable install works through an
import hook. setuptools **appends** its `_EditableFinder` to `sys.meta_path`,
i.e. *after* the ordinary `PathFinder`, and `PathFinder` walks `sys.path`, whose
`PYTHONPATH` entries come before site-packages. Checked, not inferred from a doc
page.

On Delta that is one variable (`APPTAINERENV_PYTHONPATH=$ABTEM_SRC`). On
Perlmutter it takes **two flags, and both are mandatory**:

```bash
podman-hpc run --rm --gpu \
    -e PYTHONPATH="$ABTEM_SRC" \
    -v "$ABTEM_SRC:$ABTEM_SRC" \
    ...
```

`-e PYTHONPATH=...` *replaces* the image's own `PYTHONPATH`
(`/opt/software/lammps/python`, set in the Dockerfile) rather than prepending to
it. Nothing in this suite imports `lammps`, so the launchers overwrite it; append
`:/opt/software/lammps/python` if some other run needs it back.

Forget the `-v` and `PYTHONPATH` points at a path that **does not exist inside
the container**. Python skips missing `sys.path` entries without complaint, the
container's own abTEM wins, and the checks then measure that abTEM instead: an
abTEM without the multi-GPU code forces the synchronous scheduler on GPU and
*cannot* distribute, so you get "no multi-GPU support" — or, if the image happens
to have been built from a checkout that does carry the code, a plausible-looking
run of software you did not mean to test.

**The version string cannot tell you which won**: the container's abTEM and the
branch can both report `1.1.0`. The only proof is the path. Section 0 prints
`abtem=<version>  <- <file>`, and `<file>` must be under `$ABTEM_SRC`.
`setup_env.sh` asserts exactly that on a login node, and all three launchers
re-assert it in-job and refuse to start otherwise (`benchmark_haadf_auto.sbatch`
lets you waive its probe with `SKIP_PROBE=1` — don't) — which matters, because
`verify_multigpu.py` on its own would *not* fail the job: an abTEM without
multi-GPU support is recorded `WARN` (`environment.abtem_multigpu_support`) with
the abTEM checks `SKIP`ped, and the exit status counts only `FAIL`s. A green job
that tested nothing is exactly the outcome the prechecks exist to prevent.

The mount is written `-v $ABTEM_SRC:$ABTEM_SRC` — same path inside and out — so
that `PYTHONPATH`, tracebacks, and the `abtem.__file__` printed in section 0 all
name the same location.

Because the container's abTEM is an *editable* install, binding the checkout over
the install path (`-v $ABTEM_SRC:/opt/src/abTEM`) would work equally well, and is
the pattern `../../podman-hpc.md` documents for gpaw/otherimage/gpaw-weaver/
PySlice. The launchers deliberately do not use it: `PYTHONPATH` keeps the
Perlmutter and Delta runs differing in as few places as possible, and it leaves
the container's own abTEM visible in section 0 when something goes wrong.

## The dask / dask-cuda version knot

Already solved, in the **container**, for both clusters: the image pairs
`dask-cuda` installed `--no-deps` with `dask 2026.7` (plus `nvidia-ml-py` and
`cuda-core[cu12]<1.0`), so there is **nothing to install or pin at run time**.

The full analysis — why a plain `pip install dask-cuda` cannot resolve against
this stack, why `dask==2026.1.1` must never be pinned (a `to_zarr` regression
abTEM blacklists), and the Plan-B downgrade table if the `--no-deps` pairing ever
misbehaves — is in
[`../../../delta/verification/multigpu_abtem/README.md`](../../../delta/verification/multigpu_abtem/README.md).
It is written once because the image is the same on both clusters; nothing in it
is Delta-specific.

## Node shape: 1, 2, 4 GPUs — there is no 8-GPU node

Perlmutter GPU nodes are **1× AMD EPYC 7763 (64 physical / 128 logical cores),
256 GB DDR4, 4× NVIDIA A100 40 GB** (256 nodes carry 80 GB cards, reachable with
`-C "gpu&hbm80g"`), 4× Slingshot-11. That is the whole menu:

- **GPU-count sweeps top out at 4** (`--gpu-counts 1,2,4`). Delta's launchers
  carry a commented-out `gpuA100x8` variant next to every `#SBATCH` block (and
  `delta/jobs/` adds a `gpuH200x8` template on top of that); those blocks are
  **deliberately absent here** because Perlmutter has no 8-GPU node to switch
  to. Anything wider than 4 GPUs is a multi-node problem, and
  `dask_cuda.LocalCUDACluster` is single-node by construction — a multi-node
  version would need `dask-jobqueue` or a manual scheduler/worker launch, which
  this suite does not attempt.
- **`--cpus-per-task=128`** for the single task that drives all 4 GPUs, following
  NERSC's rule of thumb `2 × ⌊64 / tasks_per_node⌋`.
- **`--gpu-bind=none`**, because one process must see all four devices; a
  per-task binding would hand the single task a subset. (Delta's suite uses
  `--gpu-bind=closest`; do not copy that here.)
- `--exclusive` on a full node gives the job all 256 GB of host RAM, which is
  what the N dask-cuda workers plus this (large) container need.
- There is **no `module reset`** on Perlmutter and no
  `--constraint="scratch&projects"` — the Delta launchers' first two lines have no
  counterpart. Source `../../env.sh` instead, for the image-store variables.

## Account, QOS, and what a run costs

- **Account**: GPU allocations carry a `_g` suffix — `#SBATCH -A <project>_g`.
  CPU accounts have no suffix, and using the wrong one mischarges the other
  allocation. **Replace `<project>_g` in every `.sbatch` here before first use**
  (`iris`, or `sacctmgr show assoc user=$USER format=account`, lists yours).
- **Constraint**: `#SBATCH -C gpu` (add `&hbm80g` only if you need 80 GB cards).
- **Charge** = `walltime × nodes × QOS factor`, on *actual* walltime, with
  Perlmutter's charge factor 1.0. A 10-minute verification on one node costs
  ~0.17 GPU node-hours; a 3-hour benchmark costs 3.

| QOS | Limits | Use it for |
|---|---|---|
| `debug` | ≤ 30 min, ≤ 8 nodes, 2 running | `multigpu_verify.sbatch` — it is a 10-minute job and the queue is short |
| `regular` | ≤ 48 h | the HAADF benchmarks |
| `interactive` | ≤ 4 h, ≤ 4 nodes, 2 running | poking at the container on a GPU node (`../../jobs/interactive_gpu.sh`) |
| `shared` | 1–2 GPUs, prorated **0.25 / 0.5** node-hr per hour | a cheap `--gpu-counts 1,2` partial sweep |

The 4-GPU point needs a whole node and therefore `regular`/`debug`; only the
1- and 2-GPU points fit in `shared`. Running the sweep split across two jobs
saves a little allocation but loses the property that makes it trustworthy — see
the note under *Benchmark* below.

## Run it

```bash
# 0. one-time: make the image visible to compute nodes, and set the store vars
. ../../env.sh                       # PODMANHPC_ADDITIONAL_STORES -> /dvs_ro mirror
../../update-image.sh otherimage     # login node only; pulls into the CFS store
podman-hpc images --digests          # record the digest with your results

# 1. point ABTEM_SRC at your 'multi-gpu-support' checkout and preflight it
export ABTEM_SRC=$SCRATCH/code/abTEM
git -C "$ABTEM_SRC" switch multi-gpu-support
./setup_env.sh                       # no venv; prints versions and where abtem came from

# 2. replace <project>_g in multigpu_verify.sbatch, then submit FROM THIS DIR
ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch            # 4 GPUs
ABTEM_SRC=$ABTEM_SRC sbatch multigpu_verify.sbatch --timing   # also time 1 vs N GPUs
```

Everything is overridable at submit time:

```bash
IMAGE=ghcr.io/<username>/otherimage:v2 ABTEM_SRC=$SCRATCH/code/abTEM-269 \
  sbatch -A <project>_g multigpu_verify.sbatch --gpus 2
```

Options worth knowing (`python verify_multigpu.py --help` for all):

- `--gpus N` — expected GPU count (default: all visible). Also caps the cluster.
- `--configs K` — frozen-phonon configurations = independent dask chunks
  (default `max(8, 2·gpus)`; keep it ≥ GPU count for full coverage).
- `--supercell`, `--sampling`, `--energy` — workload size / cost knobs.
- `--rmm-pool 20GB` — pre-allocate an RMM pool per worker (steadier timing).
- `--timing` — add a 1-GPU vs N-GPU wall-clock comparison.
- `--no-cluster` — skip the cluster; just smoke-test each GPU independently.

### Interactive smoke test

```bash
salloc -A <project>_g -C gpu -q interactive -N 1 --gpus-per-node=4 -t 01:00:00
# ...the allocation shell runs ON the compute node, so podman-hpc runs there:
PAYLOAD=$(cd ../../../shared/verification/multigpu_abtem && pwd)
podman-hpc run --rm --gpu \
    -v "$SCRATCH:$SCRATCH" -v "$HOME:$HOME" \
    -v "$PAYLOAD:$PAYLOAD" -v "$ABTEM_SRC:$ABTEM_SRC" \
    -e PYTHONPATH="$ABTEM_SRC" --workdir "$SCRATCH" \
    ghcr.io/<username>/otherimage:latest python "$PAYLOAD/verify_multigpu.py"
```

`--workdir` is there for the same reason the launchers set it: dask-cuda workers
create their spill directory in the CWD, and the image's default CWD is inside
the container, not on a mounted filesystem.

Drop the `-e PYTHONPATH` **and** the `-v "$ABTEM_SRC:..."` together to run against
the container's own abTEM: dask-cuda ships in the image, so cluster bring-up and
GPU coverage still run, and the abTEM checks either run or `SKIP` depending on
whether that image's abTEM carries the multi-GPU code — section 0 says which.
`../../jobs/interactive_gpu.sh` is the shorter route to a shell, but it mounts
only `$SCRATCH`, `$CFS`, and `$HOME` and passes no `-e PYTHONPATH`, so anything
run through it uses the container's abTEM. Use the explicit `-v`/`-e` form above
whenever you mean to test the branch.

## Benchmark (HAADF: scaling + GPU-count invariance)

`benchmark_haadf.py` runs the **same** frozen-phonon HAADF STEM image simulation
on 1, 2 and 4 GPUs and reports two things:

- **Scaling** — wall-clock, speedup, and parallel efficiency vs 1 GPU.
- **Invariance** — that the HAADF image is the *same* regardless of GPU count.
  This is the correctness gate: spreading frozen-phonon configurations / scan
  positions across GPUs must not change the answer. The dask graph (including the
  reduction over phonons) is fixed by the problem, not by the cluster, so on four
  homogeneous A100s the images should agree to near machine precision — the check
  reports the actual max relative deviation and PASSes under `--tol` (1e-4).

```bash
# full node, default STO workload; sweeps 1,2,4 GPUs internally:
ABTEM_SRC=$ABTEM_SRC sbatch -A <project>_g benchmark_haadf.sbatch

# heavier run (bump --time in the sbatch for large workloads):
... benchmark_haadf.sbatch --configs 32 --supercell 8,8,30 --sampling 0.04
```

The whole sweep runs in **one job** on one node, so the 1/2/4-GPU images are
produced by the same process, from the same structure and the same frozen-phonon
seed, and compared directly in memory. Splitting the sweep across jobs (e.g. the
1- and 2-GPU points into `shared`) weakens the invariance check to a comparison
of separate runs — do it to save allocation, not to save time.

Knobs (`--help` for all): `--structure {STO,Si}`, `--supercell nx,ny,nz`
(z = thickness), `--configs`, `--sampling`, `--energy`, `--convergence`,
`--inner/--outer` (HAADF angles; outer is clamped to the grid's antialiased
cutoff and reported), `--scan-sampling`, `--gpu-counts 1,2,4`,
`--projection {infinite,finite}` (default `infinite`),
`--precision {float32,float64}` (float64 tightens agreement), `--tol`.

Outputs (in `--output`, default `$SCRATCH/bench_haadf_<jobid>`): the structure as
`.cif` (for VESTA), `haadf_<n>gpu.npy` per GPU count, a reference PNG and
difference PNGs, and `results.json` (times, speedups, per-count max deviation,
`invariance_pass`). Exit status is non-zero if the image is not invariant.

`$SCRATCH` is **purged after 8 weeks without access** — copy anything you intend
to cite into `$CFS/<project>/` when the run finishes.

### Explicit vs automatic cluster

`benchmark_haadf.py` creates the `dask_cuda.LocalCUDACluster` **explicitly** (and
sizes each GPU-count run via `CUDA_VISIBLE_DEVICES` on the cluster) — it tests the
*bring-your-own-client* path.

`benchmark_haadf_auto.py` instead sets `config['dask.multi-gpu'] = True` and lets
abTEM start the cluster itself (`ensure_cuda_cluster`) — the *automatic* path.
Because that path always spans **all visible** GPUs, each count runs as a
**subprocess** with `CUDA_VISIBLE_DEVICES` restricted, so every child exercises
the auto-init on its own GPUs. (The `n=1` point has one visible GPU, so the auto
path correctly declines to build a cluster and runs synchronously — that is the
single-GPU reference.) The children are spawned *inside* the same container and
inherit `PYTHONPATH` and `CUDA_VISIBLE_DEVICES` from the parent, so the single
`podman-hpc run` in the launcher covers all of them. Same knobs, same outputs
(`auto_<n>gpu.npy`, `results.json` with an `auto_cluster_started` flag per count):

```bash
ABTEM_SRC=$ABTEM_SRC sbatch -A <project>_g benchmark_haadf_auto.sbatch
```

Either benchmark works against the integrated `multi-gpu-on-269` branch — point
`ABTEM_SRC` at a checkout on that branch to test the multi-GPU work together with
the #269 GPU-memory improvements. Two caveats when using these benchmarks to
check #269's claims: its memory-bounded potential chunking only matters at large
grids (push with `--sampling 0.03 --supercell 10,10,40`), and its per-GPU speedup
is `--projection finite`, float32 specific. The scaling table here shows
*multi-GPU* scaling, not #269's per-GPU speedup; for the latter compare absolute
times of the same run on the two branches at a fixed GPU count.

## What the checks mean

- **0. Environment** — versions + visible GPUs, and whether the running abTEM has
  the multi-GPU code. An abTEM without it forces the synchronous scheduler on
  GPU, so it *cannot* distribute — the branch must be on `PYTHONPATH` **and**
  mounted. Read the `<- <file>` path here, not the version: the container's own
  abTEM may report the same version as the branch.
- **1. Cluster bring-up** — one single-threaded worker per GPU;
  `is_gpu_dask_client(client)` accepts it (a multi-threaded / CPU client would be
  rejected and fall back to synchronous, by design).
- **2. GPU coverage** — each worker reports a **distinct PCI address**, proving
  one physical GPU per worker (dask-cuda pinning), and runs a real CuPy kernel.
- **3. abTEM (explicit client)** — a frozen-phonon exit-wave simulation with one
  independent chunk per configuration; the dask **task stream** must show tasks on
  **all** GPU workers. This is the direct proof of distribution.
- **4. abTEM (automatic)** — same, but driven only by
  `config['dask.multi-gpu']=True` with no pre-existing client, so abTEM starts the
  cluster itself. This is the "automatically use all GPUs" headline path.
- **5. Timing (optional)** — 1-GPU vs N-GPU wall clock. Speedup is
  workload-dependent (this workload is embarrassingly parallel over
  configurations, so it should scale near-linearly until the GPUs starve).

Exit status is non-zero if any check **FAIL**s — `WARN` and `SKIP` do not set it.
A `WARN` on distribution usually means `--configs` was below the GPU count (raise
it). A `WARN` on `environment.abtem_multigpu_support` means the branch was not
imported at all and the abTEM checks `SKIP`ped: the run exits 0 having proved
nothing, which is why the launchers precheck the import path and abort.

## Expected output (4× A100 40 GB, abridged)

```
0. Environment
  dask=2026.7.0   distributed=2026.7.0   cupy=13.5.1   dask_cuda=26.6.0
  GPU 0: NVIDIA A100-SXM4-40GB  pci=0000:03:00  40 GB
  ... (×4)
  abtem=1.1.0  <- /pscratch/sd/p/<username>/code/abTEM/abtem/__init__.py
[ PASS ] environment.abtem_multigpu_support -- is_gpu_dask_client + dask.multi-gpu
[ PASS ] environment.dask_cuda      -- dask=2026.7.0, dask_cuda expects dask ...
1. dask-cuda cluster bring-up
[ PASS ] cluster.worker_count       -- 4 workers == 4 GPUs
[ PASS ] cluster.single_threaded    -- every worker is single-threaded
[ PASS ] cluster.abtem_accepts_client -- is_gpu_dask_client(client) is True
2. GPU coverage
[ PASS ] coverage.distinct_gpus     -- 4 workers on 4 distinct GPUs
3. abTEM explicit
[ PASS ] abtem.explicit.correctness  -- exit waves (8, N, N) finite; ...
[ PASS ] abtem.explicit.distribution -- abTEM ran tasks on all 4 GPU workers
4. abTEM automatic
[ PASS ] abtem.auto.cluster_started  -- abTEM auto-started a usable dask-cuda cluster
[ PASS ] abtem.auto.correctness      -- exit waves (8, N, N) finite; ...
[ PASS ] abtem.auto.distribution     -- abTEM ran tasks on all 4 GPU workers

11 passed, 0 warnings, 0 failed, 0 skipped
```

That is the full tally for a default run (12 with `--timing`, which adds
`timing.speedup`); the lines above are abridged only in their detail text. The
`abtem=` line is the one to read first — the path after `<-` must be your
`$ABTEM_SRC`. The PCI addresses are the driver's physical view and will differ
from Delta's; only their *distinctness* is checked.

## Troubleshooting

- **`FileNotFoundError` on the payload, or `python: can't open file ...`** — a
  missing `-v`. podman-hpc mounts nothing by default; the payload directory, the
  abTEM checkout, and the output directory each need one. Print the mount list
  the launcher assembled (it echoes it) and check the path really is in there.
- **`environment.abtem_multigpu_support` WARNs, or section 0's `abtem` path is
  not under `$ABTEM_SRC`** — the branch is not actually on `sys.path` inside the
  container. Almost always the missing `-v "$ABTEM_SRC:$ABTEM_SRC"` next to
  `-e PYTHONPATH=...`: Python ignores non-existent `sys.path` entries silently.
  Note it is a `WARN`, so `verify_multigpu.py` still exits 0 — the launcher
  precheck (exit 1) and the printed path are the real signals, and the version
  number is not, since the container's abTEM can report the branch's version.
  Re-run `./setup_env.sh`, which fails loudly on exactly this.
- **`Error: short-name resolution` / image not found on the compute node** — the
  image is in the login-node store but not in a store the compute node can read.
  `source ../../env.sh` (sets `PODMANHPC_ADDITIONAL_STORES` to the `/dvs_ro`
  mirror) and use the fully qualified `ghcr.io/<username>/otherimage:latest`. An
  image you **built** rather than pulled also needs `podman-hpc migrate <tag>`.
- **The image vanished between runs** — `$SCRATCH` is purged after 8 weeks
  without access, and the default squash store lives there. Keep campaign images
  in the CFS store (`../../update-image.sh otherimage` — bare, it pulls
  `idrobolab`) and record the digest.
- **`Killed` (SIGKILL) during cluster bring-up, no traceback** — host-memory OOM:
  not enough RAM for N dask-cuda workers in this (large) container. Most common
  cause: running the job script with **`bash`**, which ignores the `#SBATCH`
  directives entirely. Fixes: submit with **`sbatch`** (`--exclusive` on a GPU
  node gives all 256 GB); or shrink the run (`--gpus 2`, fewer `--configs`).
  Section 0 prints the cgroup/job memory limit and the clusters cap each worker
  to ~0.85·(job mem)/N so a tight allocation spills instead of OOM-ing. Caveat:
  under podman-hpc that printed limit is whatever cgroup the *container* sees,
  which may not equal the Slurm step's limit — treat it as indicative, not
  authoritative, until someone confirms it on a real node.
- **`cluster.worker_count` FAIL (fewer workers than GPUs)** — check
  `CUDA_VISIBLE_DEVICES` in section 0, that `--gpus-per-node=4` was honoured, and
  that `--gpu-bind=none` is set. With a per-task binding the single task sees only
  its "own" GPU and dask-cuda makes one worker.
- **`abtem.*.distribution` FAIL/WARN** — raise `--configs`; confirm `abtem` in
  section 0 imports from `$ABTEM_SRC`.
- **`is_gpu_dask_client is False`** — the client's workers are not
  single-threaded; dask-cuda uses one thread per worker by default — don't
  override `threads_per_worker`.
- **dask-cuda import errors at run time** — NVML/driver mismatch inside the
  container. Check it on a GPU node with
  `podman-hpc run --rm --gpu $IMAGE python -P -c "import dask_cuda; from dask_cuda import LocalCUDACluster"`.

## Status

These launchers follow the conventions in `../../jobs/` (constraint, `_g`
account, QOS, `cpus-per-task`, mount loop) and the podman-hpc patterns in
`../../podman-hpc.md`, but **have not been run on Perlmutter yet** — see the
Status section of `../../jobs/README.md` for the state of the Perlmutter side of
the image. The *payloads* are the ones exercised from Delta, so a failure here is
more likely in the launcher (mounts, flags) than in the checks. Start with
`./setup_env.sh` on a login node, then the `debug`-QOS verification, before
spending node-hours on a benchmark.
