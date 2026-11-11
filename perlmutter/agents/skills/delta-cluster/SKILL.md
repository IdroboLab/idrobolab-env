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

- **There is no `$SCRATCH` on Delta — only `$SCRATCH_BASE`**, with personal scratch at
  `$SCRATCH_BASE/$USER`. **Delta itself sets neither `$SCRATCH_BASE` nor `$PROJECTS_BASE`**
  (seen on a login node, 2026-11-11): they come from the user's shell setup, which
  `delta/env.sh` derives from `DELTA_PROJECT` (`/scratch/<project>`,
  `/projects/<project>`). A job sees them only because it inherits the submitting shell's
  environment. A script that references `$SCRATCH` under `set -u` aborts
  immediately, and inherited scripts that assume it have failed on Delta. NCSA's own sample job scripts (`running_jobs.html`) claim
  "`$WORK` and `$SCRATCH` are now set" after `module reset` — that contradicts the
  failures seen here, and which is right hasn't been checked on a node, so don't depend
  on either variable: write `$SCRATCH_BASE/$USER` explicitly.
- **Run `module reset` before anything that relies on `set -u`.** It loads the Cray
  defaults (`cray-mpich` and friends); without it a job can fail on an unset
  network-targeting module.
- Container images conventionally live under `$PROJECTS_BASE/software/containers/*.sif`
  — a project-shared, non-account-specific path pattern worth reusing for any new image.
- **Every filesystem a job touches needs its own Slurm constraint/feature label — they
  don't nest or imply each other.** From NCSA's "File System Dependency Specification for
  Jobs" table (`running_jobs.html`): `/projects` (same underlying FS as `/taiga`) →
  `projects`, **`/work/hdd` → `work`** (its own label, not covered by `scratch` or
  `projects`), IME (`/ime`, itself dependent on `/work/hdd`) → `ime`, TAIGA (`/taiga`) →
  `taiga`. `/scratch` → `scratch` isn't a row of that table (re-read 2026-09-23), but
  every sample script on the same page uses `--constraint="scratch"`, so the label is
  real. `#SBATCH
  --constraint="scratch&projects&work"` for a job touching all three — a job that omits
  one isn't guaranteed to land on a node that can see that filesystem, and NCSA's docs
  note unconstrained jobs are assumed to depend on `/u` (home) only. (`scontrol update
  job=<id> Features="..."` sets the equivalent on an already-pending job.)
- **Storage tiers, per NCSA's own docs (docs.ncsa.illinois.edu, Delta user guide, Data
  Management page): neither `/projects` nor `/work/hdd` is purged — the distinction is
  quota scale and intended use, not retention.** `/projects/<project>` defaults to 500 GB
  (expandable to 1-25 TB) and is for shared/precious project data (common datasets,
  software, results). `/work/hdd/<project>` defaults to 1 TB (expandable to 1-100 TB) and
  is explicitly "the primary computation area... where I/O from jobs should occur" — large,
  regenerable job output (checkpoints, intermediate files that can be rerun if lost)
  belongs there, not in `/projects`, both to stay off the smaller/shared quota and because
  it's the tier meant for job I/O traffic. `/work/nvme` exists alongside it for jobs doing
  lots of small-file I/O. `/tmp` is the only tier actually purged here (per-node, wiped
  after each job).

Cluster-wide environment variables go in `delta/env.sh`, never in job scripts or run
instructions. It sets `SCRATCH_BASE`, `PROJECTS_BASE`, the Apptainer cache on personal
scratch, uv's cache (shared by the project) and the project's bin directory on `PATH`;
`delta/helpers/setup-user.sh` writes the `~/.bashrc` block that sources it.

## MPI and container launch

Delta's containers (built via Apptainer/Docker, typically vanilla ANL **MPICH 4.3.2**,
ch4:ofi, embedded PMI clients) are launched one of two ways, and picking the wrong one
for the job shape causes confusing failures:

- **Multi-rank CPU jobs: `srun --mpi=pmi2 apptainer exec ... python`, never `mpiexec`
  inside the container.** Verified repeatedly at up to 128 ranks on the CPU partition.
  `mpiexec`'s Hydra bootstrap auto-detects the Slurm environment and tries to exec a host
  `srun`, which does not exist inside the container — `execvp error on file srun`.
- **A single-node, in-container `mpiexec` is only safe with `-bootstrap fork`**, which
  forces local process spawn instead of Hydra's Slurm auto-detection. This does not
  extend to multi-node: multi-node jobs need the `srun`-as-host-launcher pattern above,
  not a wrapped `mpiexec`.
- GPU and multi-node MPI on Delta are less thoroughly verified here than the single-node
  CPU `srun --mpi=pmi2` path — treat a GPU/multi-node launch as needing its own smoke
  test (an 8-rank hello-world before trusting a production run), not an assumption that
  the CPU recipe transfers unchanged.
- **Interactive MPI testing needs `salloc`, not `srun --pty bash`.** A shell started by
  `srun --pty` is itself a job step, and `srun` (or `mpirun`) can't be run from inside it
  (NCSA docs). `salloc` leaves the shell on the login node holding the allocation, and
  each `srun ...` typed there — including the `srun --mpi=pmi2 apptainer exec ...` pattern
  above — launches on the allocated nodes with the salloc settings. Plain commands in that
  shell still run on the **login node**; `exit` releases the allocation early.
- **GPU jobs: `--gpu-bind=closest`** pins each task to a CPU near its GPU on the PCI
  topology, as in all of NCSA's GPU sample scripts. Multi-node NCCL (their PyTorch DDP
  example) also needs `module load aws-ofi-nccl` (the Slingshot-11 plugin) and
  `NCCL_SOCKET_IFNAME=hsn`. Neither has been tested here from inside a container.

**MPICH ch4 POSIX shared-memory collective truncation at scale** — the nastiest failure
mode seen here. Symptom around 32–64 ranks on one node:
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
truncates — so a crash here does not necessarily mean the physics was wrong, only that
results were never durably written.
Fix, no rebuild needed: `export APPTAINERENV_MPIR_CVAR_DEVICE_COLLECTIVES=none` —
disables the ch4 device/POSIX composition collectives (generic MPIR fallback), keeps
point-to-point shared memory. Verified to run clean. If that alone isn't enough, the next
escalation is `MPIR_CVAR_{BARRIER,BCAST,ALLREDUCE,REDUCE}_COMPOSITION=NM` (network-module
only), and the last resort is rebuilding MPICH with `--with-ch4-shmmods=none`.
`MPICH_SMP_SINGLE_COPY_MODE` is a *Cray* MPICH variable — it does nothing against the
vanilla ANL MPICH build most containers here actually ship.


## Hardware and partitions

Delta's Hopper GPU partition is **`gpuH200x8`** (H200, 141 GB, sm_90, max one node per
job) — there is no separate H100 partition; an inherited script or note assuming one is
stale.

Partitions per NCSA's `running_jobs.html` (read 2026-09-23). Each row is a partition
family: the base partition, plus its `-interactive` and `-preempt` variants where one
exists. Columns: max nodes per job (base / interactive; "all" = the whole partition),
and the **charge factor** — the multiplier on node-hours billed against the allocation —
for the base / interactive / preempt variants ("—" = no such variant).

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
and pushed to a registry elsewhere, then on Delta:
`apptainer build image.sif docker://<registry>/<image>:<tag>`. `delta/get-image.sh` does
this for the group image, queueing the conversion on a compute node.

The conversion is done by hand by a person, never scripted into run instructions: commands
and job scripts reference the `.sif` that is already there, and if a run needs a newer image,
say so and stop. What follows is how the conversion goes, for whoever does it.

**Do the SIF conversion on a compute node, not a login node.** NCSA's docs send large,
compute-heavy work to compute nodes because login nodes are shared. The conversion
unpacks the whole image and then runs a multithreaded `mksquashfs` over it. Converting a
multi-GB image on `dt-login03` failed at the final step: `while creating squashfs:
.../mksquashfs command failed: exit status 134: malloc(): invalid size (unsorted)`
(2026-09-23). The cause isn't confirmed, and it hasn't yet been checked whether a compute
node avoids it. The first things to try are:

1. An interactive `srun` job on `cpu` (a plain `srun --pty bash` is fine here, since no
   MPI is involved).
2. `APPTAINER_TMPDIR` pointed at that node's local `/tmp` and `APPTAINER_CACHEDIR` under
   `$SCRATCH_BASE/$USER`.
3. If it still crashes, `--mksquashfs-args "-processors 4"` to limit the threads.

The layer cache survives a failed build, so a retry skips the download.
