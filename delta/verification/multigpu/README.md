# abTEM multi-GPU verification (Delta)

Confirms that abTEM actually distributes a GPU simulation across **every GPU on a
node**, using the multi-GPU support on the abTEM `multi-gpu-support` branch (lazy
GPU computes routed through a `dask_cuda` cluster, one worker process per GPU).

| File | Purpose |
|---|---|
| `verify_multigpu.py` | The verification payload — environment report + cluster/coverage/distribution checks. Portable; runs anywhere with CuPy + dask-cuda. |
| `setup_env.sh` | One-time builder for the overlay venv (just the abTEM branch; dask-cuda is in the container). |
| `multigpu_verify.sbatch` | Slurm submission for `gpuA100x4` (8-GPU variant inline). |

## The dask / dask-cuda version knot (handled in the container)

The container (`otherimage_delta.sif`) ships `dask 2026.7.0` and `cupy-cuda12x
13.5.1`. The newest released `dask-cuda` (26.6.0) hard-pins
`rapids-dask-dependency==26.6.*` → `dask==2026.1.1`, and both abTEM 1.0.9 and the
`multi-gpu-support` branch *exclude* `dask 2026.1.*`. A plain `pip install
dask-cuda` would therefore fail to resolve (or downgrade the whole stack).

The **container build** resolves this once (see
`containers/otherimage/otherimage_delta.def`): dask-cuda is installed
`--no-deps` against the existing `dask 2026.7`, with only its non-dask runtime
deps added (`nvidia-ml-py`, `cuda-core[cu12]<1.0` — the 1.x line drops the
`cuda.core.experimental` namespace dask-cuda 26.6 imports). This pairing is
verified to import against `distributed 2026.7`; the runtime cluster is what
this job checks on a GPU node. When a dask-cuda built for `dask 2026.7` ships
(RAPIDS ≥ 26.8), the `.def` switches to a normal `pip install dask-cuda`.

So the **overlay venv only carries the abTEM branch** (the container's abTEM
1.0.9 has no multi-GPU code); it installs cleanly against the container's
`dask 2026.7` with no version gymnastics.

## Run it

```bash
# 0. once (no internet needed with a local checkout):
module reset
export ABTEM_SRC=$SCRATCH/code/abTEM        # your 'multi-gpu-support' checkout
git -C "$ABTEM_SRC" switch multi-gpu-support
./setup_env.sh                              # builds $SCRATCH/venvs/abtem_mgpu

# 1. edit the --account line in multigpu_verify.sbatch (see `accounts`), then:
sbatch multigpu_verify.sbatch               # 4 GPUs
sbatch multigpu_verify.sbatch --timing      # also time 1 vs N GPUs
```

Options worth knowing (`python verify_multigpu.py --help` for all):

- `--gpus N` — expected GPU count (default: all visible). Also caps the cluster.
- `--configs K` — frozen-phonon configurations = independent dask chunks
  (default `max(8, 2·gpus)`; keep it ≥ GPU count for full coverage).
- `--supercell`, `--sampling`, `--energy` — workload size / cost knobs.
- `--rmm-pool 20GB` — pre-allocate an RMM pool per worker (steadier timing).
- `--timing` — add a 1-GPU vs N-GPU wall-clock comparison.
- `--no-cluster` — skip the cluster; just smoke-test each GPU independently.

Quick interactive smoke test (no overlay venv, container abTEM 1.0.9). Because
dask-cuda ships in the container, the cluster bring-up and GPU-coverage checks
still run; only the abTEM-distribution checks are skipped (they need the branch):

```bash
./interactive_gpu.sh                        # from ../../jobs/, gets you a GPU shell
apptainer exec --nv $SIF python verify_multigpu.py            # cluster + coverage
apptainer exec --nv $SIF python verify_multigpu.py --no-cluster   # per-GPU only
```

## What the checks mean

- **0. Environment** — versions + visible GPUs, and whether the running abTEM
  has the multi-GPU code. Container abTEM 1.0.9 always forces the synchronous
  scheduler on GPU, so it *cannot* distribute — you must use the overlay venv.
- **1. Cluster bring-up** — one single-threaded worker per GPU;
  `is_gpu_dask_client(client)` accepts it (a multi-threaded / CPU client would be
  rejected and fall back to synchronous, by design).
- **2. GPU coverage** — each worker reports a **distinct PCI address**, proving
  one physical GPU per worker (dask-cuda pinning), and runs a real CuPy kernel.
- **3. abTEM (explicit client)** — a frozen-phonon exit-wave simulation with one
  independent chunk per configuration; the dask **task stream** must show tasks
  on **all** GPU workers. This is the direct proof of distribution.
- **4. abTEM (automatic)** — same, but driven only by
  `config['dask.multi-gpu']=True` with no pre-existing client, so abTEM starts
  the cluster itself. This is the "automatically use all GPUs" headline path.
- **5. Timing (optional)** — 1-GPU vs N-GPU wall clock. Speedup is
  workload-dependent (this workload is embarrassingly parallel over
  configurations, so it should scale near-linearly until the GPUs starve).

Exit status is non-zero if any check **FAIL**s. A `WARN` on distribution usually
means `--configs` was below the GPU count (raise it).

## Expected output (4× A100, abridged)

```
0. Environment
  dask=2026.7.0   distributed=2026.7.0   cupy=13.5.1   dask_cuda=26.6.0
  GPU 0: NVIDIA A100-SXM4-40GB  pci=0000:07:00  40 GB
  ... (×4)
  abtem=1.1.0
[ PASS ] environment.abtem_multigpu_support -- is_gpu_dask_client + dask.multi-gpu
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
[ PASS ] abtem.auto.distribution     -- abTEM ran tasks on all 4 GPU workers

8 passed, 0 warnings, 0 failed, 0 skipped
```

## Troubleshooting

- **`cluster.worker_count FAIL` (fewer workers than GPUs)** — check
  `CUDA_VISIBLE_DEVICES` and that Slurm gave the job all requested GPUs
  (`--gpus-per-node`); dask-cuda makes one worker per visible GPU.
- **`abtem.*.distribution FAIL/WARN`** — raise `--configs`; confirm the venv's
  abTEM is the branch (`environment.abtem_multigpu_support` should PASS).
- **`is_gpu_dask_client is False`** — the client's workers are not
  single-threaded; dask-cuda uses one thread per worker by default — don't
  override `threads_per_worker`.
- **dask-cuda import errors at run time** — a NVML/driver mismatch inside the
  container; verify with `apptainer exec --nv $SIF python -c "import
  dask_cuda; from dask_cuda import LocalCUDACluster"` on a GPU node.
