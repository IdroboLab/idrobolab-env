---
name: delta-cluster
description: Conventions and gotchas for running jobs on NCSA Delta — Slurm/Cray environment quirks, Apptainer container launch patterns, MPICH (ch4:ofi) traps, partitions, charge factors and job policy (interactive/preempt queues, defaults, requeue), building a .sif on Delta. Use when writing or debugging a Delta sbatch/salloc/srun script, choosing a partition or estimating allocation cost, choosing an MPI launch pattern for a container on Delta, converting an image with apptainer build, or diagnosing a Delta-specific job failure (collective truncation, srun/mpiexec errors, editable-install shadowing, mksquashfs crash).
---

# NCSA Delta conventions

The group's files for Delta are `delta/` in the idrobolab-env clone: `delta/AGENTS.md`
(conventions for editing them), `delta/jobs/README.md` (the job templates, their partitions
and how MPI is launched) and `docs/delta/README.md` (getting started, uv and its shared
cache). This skill adds measured gotchas and NCSA policy to them. Work inside the group image
is the `idrobolab-container` skill.

## Filesystem and environment

- **Use `$SCRATCH_BASE/$USER` for personal scratch, never `$SCRATCH`.** Delta itself sets
  neither `$SCRATCH_BASE` nor `$PROJECTS_BASE` (login node, 2026-11-11): `delta/env.sh`
  derives them from `DELTA_PROJECT` (`delta/AGENTS.md`), and a job sees them only because it
  inherits the submitting shell's environment. A script that expands an unset `$SCRATCH`
  under `set -u` aborts. NCSA's sample job scripts (`running_jobs.html`) say "`$WORK` and
  `$SCRATCH` are now set" after `module reset`. Measured 2026-11-11: on a login node both
  are still unset after it; inside a job step Slurm sets `SCRATCH=/scratch/<project>/$USER`
  and `WORK=/projects/<project>/$USER` (`/projects`, not `/work/hdd`). A script that also
  runs on a login node therefore cannot use them.
- **Run `module reset` before anything that relies on `set -u`.** It loads the Cray
  defaults (`PrgEnv-gnu`, `cray-mpich`, `craype-network-ofi`, `cudatoolkit`); without it a
  job can fail on an unset network-targeting module. While it runs, Lmod can warn that
  "'cray-mpich' requires a network targeting module"; the warning is harmless when
  `module list` afterwards shows `craype-network-ofi`.
- **Every filesystem a job touches needs its own Slurm constraint/feature label — they
  don't nest or imply each other.** From NCSA's "File System Dependency Specification for
  Jobs" table (`running_jobs.html`): `/projects` (same underlying FS as `/taiga`) →
  `projects`, **`/work/hdd` → `work`** (its own label, not covered by `scratch` or
  `projects`), IME (`/ime`, itself dependent on `/work/hdd`) → `ime`, TAIGA (`/taiga`) →
  `taiga`. `/scratch` → `scratch` isn't a row of that table (2026-09-23), but every sample
  script on the same page uses `--constraint="scratch"`, so the label is real. Use
  `#SBATCH --constraint="scratch&projects&work"` for a job touching all three — a job that
  omits one isn't guaranteed to land on a node that can see that filesystem, and NCSA's docs
  note unconstrained jobs are assumed to depend on `/u` (home) only. (`scontrol update
  job=<id> Features="..."` sets the equivalent on an already-pending job.)
- **Storage tiers, per NCSA's Delta user guide (Data Management page): neither `/projects`
  nor `/work/hdd` is purged; they differ in quota and intended use.** `/projects/<project>`
  defaults to 500 GB and is for shared project data (common datasets, software, results).
  `/work/hdd/<project>` defaults to 1000 GB and is what NCSA now calls the scratch
  volume; `/work/nvme` is available on request. `/tmp` is per node and wiped after each job. That page gives no quota or purge rule
  for `/scratch`. The group keeps job output and caches under `$SCRATCH_BASE/$USER`
  (`delta/AGENTS.md`, *What lives where*).

Cluster-wide environment variables go in `delta/env.sh`, never in job scripts or run
instructions; `delta/AGENTS.md` says what it sets.

## MPI and container launch

The group image carries vanilla ANL **MPICH 4.3.2** (ch4:ofi, embedded PMI clients). Which
launch pattern goes with which job shape, and which of them has been run, is in
`delta/jobs/README.md` (*How MPI is launched*); the templates implement it. In short:

- **One node: `mpiexec -bootstrap fork` inside the container, with no outer `srun`.**
  Without `-bootstrap fork`, Hydra detects the Slurm allocation and tries to exec a host
  `srun`, which does not exist inside the container: `execvp error on file srun`.
- **Several nodes: the multi-node template launches `apptainer exec ... python` with `srun`
  on the host.** `srun --mpi=list` offers `none`, `pmix`, `pmi2` and `cray_shasta`, and
  `srun --mpi=pmi2 apptainer exec ...` with the image's own MPICH and no host binds ran 4
  ranks over 2 `cpu` nodes (2026-11-11).
- Give a GPU or multi-node MPI launch its own smoke test (a small hello-world, as in the
  first-run checklist of `delta/jobs/README.md`) before a production run; the single-node CPU recipe does not transfer unchanged.
- **Interactive MPI testing needs `salloc`, not `srun --pty bash`.** A shell started by
  `srun --pty` is itself a job step, and `srun` (or `mpirun`) can't be run from inside it
  (NCSA docs). `salloc` leaves the shell on the login node holding the allocation, and
  each `srun ...` typed there launches on the allocated nodes with the salloc settings.
  Plain commands in that shell still run on the **login node**; `exit` releases the allocation early.
- **GPU jobs: `--gpu-bind=closest`** pins each task to a CPU near its GPU on the PCI
  topology, as in all of NCSA's GPU sample scripts. Multi-node NCCL (their PyTorch DDP
  example) also needs `module load aws-ofi-nccl` (the Slingshot-11 plugin) and
  `NCCL_SOCKET_IFNAME=hsn`. Neither has been tested from inside the group image.

**MPICH ch4 POSIX shared-memory collective truncation at scale.** Observed with an earlier
image of the same MPICH build; symptom around 32–64 ranks on one node:
```
MPI_Barrier -> MPIDI_Barrier_intra_composition_alpha -> MPIDI_POSIX_mpi_bcast ->
MPIR_Bcast_intra_binomial -> MPIDIG_copy_from_unexp_req:
Message from rank 0 and tag 2 truncated; 1 bytes received but buffer size is 8
```
Triggered by collective-heavy operations on the full-rank communicator at scale with a
large enough problem (observed with GPAW's `augment_grids=True`, which moves grid/XC
collectives onto the full communicator instead of a smaller domain sub-communicator) —
**not reproducible off Delta**, even with a similarly (or more) oversubscribed rank count
locally, so it appears tied to this specific interconnect/MPICH build rather than being a
generic MPICH bug. The SCF/computation itself can complete correctly before a
*post*-computation collective (e.g. a barrier before a store/write step) is what actually
truncates — so this crash does not necessarily mean the physics was wrong, only that
results were never durably written.
Fix, no rebuild needed: `export APPTAINERENV_MPIR_CVAR_DEVICE_COLLECTIVES=none` —
disables the ch4 device/POSIX composition collectives (generic MPIR fallback), keeps
point-to-point shared memory. That run then completed. If that alone isn't enough, the next
escalation is `MPIR_CVAR_{BARRIER,BCAST,ALLREDUCE,REDUCE}_COMPOSITION=NM` (network-module
only), and the last resort is rebuilding MPICH with `--with-ch4-shmmods=none`.
`MPICH_SMP_SINGLE_COPY_MODE` is a *Cray* MPICH variable — it does nothing against the
vanilla ANL MPICH build in the image.

## Hardware and partitions

Delta's Hopper GPU partition is **`gpuH200x8`** (H200, 141 GB, sm_90, max one node per
job); there is no separate H100 partition.

Partitions per NCSA's `running_jobs.html` (read 2026-09-23). Each row is a partition
family: the base partition, plus its `-interactive` and `-preempt` variants where one
exists. Columns: max nodes per job (base / interactive; "all" = the whole partition),
and the **charge factor**, the multiplier on the service units (SU) a job is billed, for
the base / interactive / preempt variants ("—" = no such variant). What one SU is, and the
factor of each job template, is in `delta/jobs/README.md`.

| Partition family | Node type | Max nodes (base / int.) | Charge (base / int. / preempt) |
|---|---|---|---|
| `cpu` | CPU (128 cores, 252 GB) | all / 4 | 1.0 / 2.0 / 0.5 |
| `gpuA100x4` | 4× A100 | all / 4 | 1.0 / 2.0 / 0.5 |
| `gpuA100x8` | 8× A100 | all / 2 | 1.5 / 3.0 / — |
| `gpuH200x8` | 8× H200 | 1 / 1 | 3.0 / 6.0 / — |
| `gpuA40x4` | 4× A40 (64 cores, 252 GB) | all / 4 | 0.5 / 1.0 / 0.25 |
| `gpuMI100x8` | 8× AMD MI100 | all / all | 0.25 / 0.5 / — |

Base and preempt partitions allow 48 h, interactive ones 1 h. The core/RAM figures are
from the node login banners in NCSA's own examples, not from a spec sheet. The partition
list changes over time, so check with `sinfo -a` before trusting a hard-coded name.

- **The Slurm account is `<project>-delta-cpu` for the CPU partitions and `<project>-delta-gpu` for
  the GPU ones (`accounts` lists them), charged separately.** With `DELTA_PROJECT` exported and
  `delta/env.sh` sourced, the `sbatch` and `salloc` functions of `delta/env.sh` add the right `-A`
  (partition `gpu*` or GPUs requested: `-delta-gpu`, else `-delta-cpu`); an `-A` of the user's own
  wins, and `srun` is not covered (`docs/delta/README.md`, *`sbatch` and `salloc` add the account*).
  In a shell that has not sourced `env.sh`, a template's `<project>` placeholder is rejected.
- **An `-interactive` partition costs 2× the base rate, and you get 1 running + 2 queued
  jobs per user.** It's for quick checks, not for real work.
- **`-preempt` is half price, but only use it for jobs that checkpoint.** A preempted job
  is guaranteed 10 minutes of runtime (`PreemptExemptTime`). After that it gets
  `SIGTERM`+`SIGCONT`, and 5 minutes later (`GraceTime=300`) another `SIGTERM` plus
  `SIGKILL`. The grace window is only useful if the job traps `SIGTERM` and writes a
  checkpoint.
- **Defaults if unspecified: 1000 MB memory per core and 30 minutes wall time.** A job
  that sets neither `--mem` nor `--time` gets both silently.
- **Nodes are shared by default.** For a whole node, request all of its resources or add
  `--exclusive --mem=0`. MIG (A100 slicing) isn't supported.
- **No automatic requeue** (the default since 2022-12). `--requeue` turns it on, but a
  requeued job reruns the batch script **from the top**, so it only makes sense if the
  script resumes from checkpoints.
- `NODELIST(REASON)` = `MaxGRESPerAccount` in `squeue` means the user or project has hit
  its per-partition core/GPU cap. The job isn't broken; it's waiting for that usage to
  drop.
- **Space out many Python-heavy jobs that start together** with
  `sbatch --dependency=after:<prev_jobid>+5` (start 5 min after the previous one *starts*;
  NCSA recommends at least 3). Many Python interpreters loading at once slow down the
  shared filesystem. Check the submit line afterwards with
  `sacct --job=<id> --format=submitline -P`.
- **You can `ssh` into any node of your own running job** (node names from `squeue -u
  $USER`) to watch it with `top -u $USER`, `free`, `nvidia-smi`, or `nvtop` (`module load
  nvtop`).

## Building and shipping a container image

Delta runs Apptainer, not Docker, and won't build an image in-cluster: the image is built
and pushed to a registry elsewhere, then converted on Delta with
`apptainer build image.sif docker://<registry>/<image>:<tag>`. `delta/get-image.sh` does
this for the group image (`docs/delta/README.md`, *Getting started*).

**Do the SIF conversion on a compute node, not a login node.** The conversion unpacks the
whole image and then runs a multithreaded `mksquashfs` over it. On a login node, converting
a multi-GB image failed at the final step: `while creating squashfs: .../mksquashfs command
failed: exit status 134: malloc(): invalid size (unsorted)` (2026-09-23); the cause isn't
confirmed. `get-image.sh` therefore queues itself on a compute node, puts
`APPTAINER_TMPDIR` on that node's local `/tmp` and `APPTAINER_CACHEDIR` under
`$SCRATCH_BASE/$USER`, and limits the threads with `--mksquashfs-args "-processors N"`; do
the same for any other image.

The layer cache survives a failed build, so a retry skips the download.

**A `.sif` is read-only at run time.** A write into the image (a `pip install` into
`/opt/venv`) fails with `[Errno 30] Read-only file system`. `apptainer exec --writable-tmpfs`
adds a temporary in-memory overlay, discarded when the process ends. That overlay is 64 MiB on
Delta: a cache written there (Numba's, under the installed packages) or the test dependencies
of abTEM and GPAW together fill it with `[Errno 28] No space left on device`. Point caches at a
directory under `$SCRATCH_BASE/$USER` (`NUMBA_CACHE_DIR`), and for larger installs use an
overlay image on scratch instead, which works without fakeroot:
`apptainer overlay create --size 2048 <dir>/overlay.img`, then
`apptainer exec --overlay <dir>/overlay.img ...`; delete the file afterwards.
