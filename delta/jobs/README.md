# Slurm submission files for another image's container on Delta

Template job scripts per partition. All take the payload as arguments
(`sbatch <script>.sbatch my_script.py [args...]`), locate the image via
`$SIF` (default `$PROJECTS_BASE/software/containers/otherimage_delta.sif`, overridable at
submit time with `SIF=... sbatch ...`), and bind `/projects`, `/scratch`,
`/work` when present. Before first use, replace `<project>` in the
`--account` lines — run `accounts` to list your charge accounts
(`<project>-delta-cpu` for CPU partitions, `<project>-delta-gpu` for GPU
partitions; they are charged separately).

## Script ↔ partition matrix

| Script | Partition | Resources | Charge factor | Intended use |
|---|---|---|---|---|
| `gpaw_cpu_singlenode.sbatch` | `cpu` | 64 ranks (≤128), 124 GB | 1.0 | GPAW MPI up to one node — **verified launch pattern** (in-container `mpiexec`) |
| `gpaw_cpu_multinode.sbatch` | `cpu` | 4 nodes × 128 ranks | 1.0 | Large GPAW SCF — Cray-MPICH injection, **untested, verify first** |
| `gpu_a100_1gpu.sbatch` | `gpuA100x4` | 1 A100, 16 cores, 62 GB | 1.0 | Single-GPU dev/production (abTEM, orb, torch) |
| `gpu_a100x4.sbatch` | `gpuA100x4` | 4 A100, 64 cores, 208 GB | 1.0 | Full quad-A100 node |
| `gpu_a100x8.sbatch` | `gpuA100x8` | 8 A100, 128 cores, ~1.9 TB | 1.5 | Many-GPU / 2 TB-host-memory jobs |
| `gpu_h200x8.sbatch` | `gpuH200x8` | 8 H200 141GB, 96 cores, ~1.9 TB | 3.0 | FP64/complex128 flagship runs (EMCD, exact-S₂); max **1 node/job**; Intel CPUs |
| `gpu_a40_1gpu.sbatch` | `gpuA40x4` | 1 A40, 16 cores, 50 GB | 0.5 | Cheapest GPU: dev/light CUDA — weak FP64, not for production physics |
| `interactive_gpu.sh` | `gpuA100x4-interactive` | 1 GPU, 1 h | 2.0 | Shell inside the container on a GPU node (helper, not sbatch) |

Charging (from NCSA's accounting docs): 1 SU = 1 core-hour (≤2 GB/core) or
1 GPU-hour; you're billed the larger of cores vs memory fraction. GPU-hour
equivalents: quad-node GPUs = 16 cores / 62.5 GB; 8-way A100 = 16 cores /
250 GB; H200 = 12 cores / 250 GB. `-interactive` queues cost 2× their batch
partition, `-preempt` 0.5× (10 min preemption protection). Max wall time is
48 h on batch partitions, 1 h interactive; default is 30 min, so always set
`--time`.

## How MPI is launched (important)

Since Delta's Dec-2025 RH9 upgrade, **Cray MPICH launched by plain `srun`
is the only supported MPI** — there is no `mpirun` on the host and
`--mpi=pmi2` is no longer documented. Consequences for this container:

1. **Single node (≤128 ranks)** — `gpaw_cpu_singlenode.sbatch` runs
   `mpiexec` *inside* the container (hydra + container MPICH). No host
   integration, no PMI wiring, verified working on the dev machine.
   Prefer this until multi-node is truly needed.
2. **Multi node** — `gpaw_cpu_multinode.sbatch` uses the Apptainer
   "hybrid"/MPICH-ABI model (as on HPE Cray EX sites): it binds the host
   Cray MPICH ABI libs (`$CRAY_MPICH_DIR/lib-abi-mpich`, both provide
   `libmpi.so.12`) over `/opt/software/mpich/lib`, binds `/opt/cray` for
   Cray's PMI/libfabric/cxi dependencies, and injects **only** the specific
   Slingshot system libs (`libcxi` et al.) via `APPTAINER_CONTAINLIBS` —
   crucially **never** binding `/usr/lib64` onto `LD_LIBRARY_PATH`, which
   would shadow the container's newer glibc and break every binary. Then
   `srun --mpi=pmi2` drives the ranks with native Slingshot transport.
   **This is untested on Delta and the paths are inferred from analogous
   Cray-EX sites**, not the live Delta docs (which block automated fetches)
   — the script has a "VERIFY ON DELTA" block; on first use confirm
   `$CRAY_MPICH_DIR/lib-abi-mpich/libmpi.so.12` exists, run
   `ldd /usr/lib64/libcxi.so.1` for the exact sonames, `srun --mpi=list`
   for the PMI plugin, then a 2-node hello-world
   (`python -c "from gpaw.mpi import world; print(world.rank, world.size)"`).
3. **Fallback** — if injection misbehaves, the container's own MPICH still
   works via `srun --mpi=pmi2` with no host binds (correct results, TCP
   transport — fine for modest rank counts). The multinode script has this
   as a commented block at the bottom. If `--mpi=pmi2` itself is rejected,
   `srun --mpi=list` shows the available plugins (try `pmix`/`cray_shasta`).

GPU scripts run a single Python process (no MPI); switch the payload to
`mpiexec -n <N> python ...` for in-container MPI+GPU hybrids.

## First-run checklist

```bash
# on Delta, once:
accounts                                   # find <project>-delta-{cpu,gpu}
mkdir -p $PROJECTS_BASE/software/containers
# transfer the image (from the dev machine):
#   scp otherimage_delta.sif <user>@login.delta.ncsa.illinois.edu:$PROJECTS_BASE/software/containers/
sha256sum $PROJECTS_BASE/software/containers/otherimage_delta.sif   # record for provenance
export APPTAINER_CACHEDIR=$SCRATCH/.apptainer        # keep caches off $HOME (quota)

# smoke tests (interactive or short jobs):
apptainer exec $SIF python -c "import gpaw, otherimage; print(gpaw.__version__)"
apptainer exec $SIF mpiexec -n 4 python -c "from gpaw.mpi import world; print(world.rank, world.size)"
srun --mpi=list                                      # note available PMI plugins
# on a GPU node:
apptainer exec --nv $SIF python -c "import torch; print(torch.cuda.get_device_name(0))"
```

Note the A100/A40 nodes are AMD Milan while H200 nodes are Intel Xeon —
both run the image's `x86-64-v3` code; no per-partition images needed
(A40 sm_86 / A100 sm_80 / H200 sm_90 are all in the shipped fat wheels).
