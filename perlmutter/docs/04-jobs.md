# 4. Jobs and queues

## Login nodes vs compute nodes

**Login nodes** are shared by everyone: use them to edit, compile, submit jobs and run
short tests (a few minutes, a few cores). NERSC kills processes that use too much
there. Everything heavier runs on **compute nodes**: either interactively with
`salloc`, or as a batch job with `sbatch`.

| | CPU node | GPU node |
|---|---|---|
| CPUs | 2× AMD EPYC 7763: 128 cores / 256 hardware threads | 1× AMD EPYC 7763: 64 cores / 128 hardware threads |
| Memory | 512 GB | 256 GB |
| GPUs | — | 4× NVIDIA A100, 40 GB each (some nodes 80 GB: `-C 'gpu&hbm80g'`) |

## Accounts and cost

Jobs are charged in node-hours to the group allocation:

- **`-A <project>`** for CPU jobs (`-C cpu`)
- **`-A <project>_g`** for GPU jobs (`-C gpu`)

The hours left are shown in <https://iris.nersc.gov> under project <project>. A whole node
costs one node-hour per hour **whether you use it or not**, so an idle interactive
session burns hours too.

The QOS (`-q`) picks the queue. One row per QOS; "Charge" is node-hours per hour of
wall time.

| QOS | For | Max time | Charge |
|---|---|---|---|
| `debug` | quick tests before a long run | 30 min | whole nodes |
| `regular` | normal batch jobs | 48 h | whole nodes |
| `shared` | batch jobs on **part** of a node | 48 h | the fraction of the node you hold |
| `interactive` | `salloc` on whole nodes (max 4) | 4 h | whole nodes |
| `shared_interactive` | `salloc` on part of a node | 4 h | the fraction of the node you hold |
| `preempt` | long jobs that can be restarted: guaranteed 2 h, then may be stopped | 48 h | 1.0 for the first 2 h, then 0.25 (GPU) / 0.5 (CPU) |

**Rule: 1 or 2 GPUs → `shared` / `shared_interactive`.** A 1-GPU slice (1 A100,
16 cores, ~64 GB) costs 0.25 node-hours per hour. `-q interactive --gpus 1` costs four
times as much, because you pay for the whole node and use a quarter of it. In a shared
QOS, always give the CPU count explicitly: 32 hardware threads per GPU (`-c 32` for
1 GPU, `-c 64` for 2).

## Interactive sessions (`salloc`)

`salloc` waits for the resources, then gives you a shell **on the compute node**.
`exit` ends the session and stops the charge.

```bash
# 1 GPU (the usual choice)
salloc -C gpu -q shared_interactive -A <project>_g -t 01:00:00 -n 1 -c 32 --gpus-per-task=1

# 2 GPUs: note --gpus=2, not --gpus-per-task=2 (the shared queue rejects that)
salloc -C gpu -q shared_interactive -A <project>_g -t 01:00:00 -n 1 -c 64 --gpus=2

# a whole GPU node (4 GPUs)
salloc -C gpu -q interactive -A <project>_g -t 01:00:00 -N 1 --gpus 4

# part of a CPU node: 16 cores, ~60 GB
salloc -C cpu -q shared_interactive -A <project> -t 01:00:00 -n 1 -c 32
```

`hostname` should now print a compute node (`nid...`), not `login...`. Run programs
inside the session with `srun`, e.g. `srun python script.py`. Careful: `salloc
<command>` (a command on the same line) runs that command on the **login node**.

For a shell inside the group container on 1 or 2 GPUs, `interactive_gpu_shared.sh` does
the `salloc` and starts the container ([page 6](06-containers.md#interactive-shell-in-the-container));
`interactive_gpu.sh` does the same on a whole node. Running abTEM this way: [page 7](07-abtem.md).

## Batch jobs (`sbatch`)

Ready-made templates are in
[`~/idrobolab-env/perlmutter/jobs/`](../jobs/). Most run your script
inside the group container ([page 6](06-containers.md)) and take the script as an
argument:

```bash
cd /global/cfs/cdirs/<project>/projects/<dir>        # output files land here
sbatch ~/idrobolab-env/perlmutter/jobs/gpu_1gpu_shared.sbatch my_script.py
```

| Template | Resources |
|---|---|
| `debug_gpu.sbatch` | 1 GPU for up to 20 min, but billed as a whole node. For a quick first test of your script |
| `gpu_1gpu_shared.sbatch` | 1 GPU, shared, 4 h. **The default for GPU work** |
| `gpu_2gpu_shared.sbatch` | 2 GPUs, shared, 4 h |
| `gpu_4gpu_node.sbatch` / `gpu_4gpu_hbm80g.sbatch` | a whole node, 4×A100 40 GB / 80 GB |
| `gpu_multinode_mpi.sbatch` | 2 nodes, one MPI rank per GPU |
| `gpaw_cpu_singlenode.sbatch` / `gpaw_cpu_multinode.sbatch` | GPAW with MPI on 1 / 4 CPU nodes |
| `abtem_uv_gpu_shared.sbatch` | 1 or 2 GPUs, shared: abTEM from your own uv environment instead of the container ([page 7](07-abtem.md)) |
| `abtem_uv_gpu_node.sbatch` | a whole node: four independent single-GPU abTEM runs (a sweep) from your uv environment |

To change the time, name or resources, copy a template into your project folder and
edit its `#SBATCH` lines, or override them on the command line
(`sbatch -t 08:00:00 -J myrun ...`). Details and pitfalls: [`../jobs/README.md`](../jobs/README.md).

A minimal job of your own, here a uv script ([page 5](05-python-uv.md)) on part of a
CPU node:

```bash
#!/bin/bash
#SBATCH -A <project>
#SBATCH -C cpu
#SBATCH -q shared
#SBATCH -n 1
#SBATCH -c 16                 # 16 hardware threads = 8 cores
#SBATCH -t 02:00:00           # always set a time limit
#SBATCH -J analysis
#SBATCH -o %x_%j.out          # <job name>_<job id>.out
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=<your email>

export OMP_NUM_THREADS=8
srun uv run --script analyse.py
```

Submit it with `sbatch analysis.sbatch`. `sbatch --test-only analysis.sbatch` checks
the request against the queue rules without submitting it.

## Watching your jobs

| What | Command |
|---|---|
| My jobs (all / running / pending) | `squeue --me` (or `q` / `sr` / `sp`) |
| Same, NERSC's nicer view | `sqs` |
| Expected start time | `squeue --me --start` |
| Why is it pending? | `squeue --me -o "%i %q %T %r"`, or `scontrol show job <jobid>` |
| Cancel one / all of mine | `scancel <jobid>` / `scancel -u $USER` |
| Finished jobs of the last week | `sacct -X --starttime=now-7days --format=JobID,JobName%20,QOS,State,Elapsed,ExitCode` |
| Hours left | <https://iris.nersc.gov> → project <project> |
| Disk usage | `showquota` ([page 3](03-storage-and-transfer.md#checking-usage)) |
| Outages and maintenance | <https://www.nersc.gov/live-status/motd/> |

Perlmutter's clock, and every time it prints, is **US Pacific time**.
