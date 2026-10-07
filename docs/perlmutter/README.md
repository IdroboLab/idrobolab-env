# Perlmutter: getting started

A step-by-step introduction for group members (NERSC project **<project>**), from a new
account to running jobs, Python, the group container, Jupyter and Nion Swift. Work
through the pages in order; each builds on the ones before. The pages are part of the
group repository [IdroboLab/idrobolab-env](https://github.com/IdroboLab/idrobolab-env),
which every member clones to `~/idrobolab-env` on Perlmutter. The reference pages one
level up ([`../`](../)) hold the details, the troubleshooting and the maintainer
instructions.

| # | Page | What you set up or learn |
|---|---|---|
| 1 | [Account and login](01-login.md) | NERSC account, MFA, `sshproxy` (Windows / macOS / Linux), SSH config |
| → | [GitHub and git](../01-github.md) | GitHub account, SSH key, your clone of `idrobolab-env` (repo-wide page) |
| 2 | [Shell and group setup](02-shell-setup.md) | oh-my-bash, the group environment |
| 3 | [Storage and data transfer](03-storage-and-transfer.md) | which file system for what, quotas, rsync, Globus, HPSS |
| 4 | [Jobs and queues](04-jobs.md) | accounts and cost, `salloc`, `sbatch`, job templates, watching jobs |
| 5 | [Python with uv](05-python-uv.md) | scripts, projects and environments |
| 6 | [The idrobolab container](06-containers.md) | the ready-made GPU software stack |
| 7 | [abTEM on Perlmutter](07-abtem.md) | run abTEM on 1–4 GPUs: in the container, or from your own uv environment |
| 8 | [Jupyter](08-jupyter.md) | notebooks on jupyter.nersc.gov or on your own node |
| 9 | [ThinLinc and Nion Swift](09-thinlinc-nionswift.md) | remote desktop, Nion Swift on a compute node |
| 10 | [Coding agents](10-coding-agents.md) | Claude Code and Codex on Perlmutter |

How we work together (data layout, compute etiquette, provenance) is collected in the
**[group conventions](conventions.md)**, a first draft.

## Overview

```
 your laptop
   │  sshproxy key (24 h)
   ├── ssh perlmutter ─────▶ login nodes ── salloc / sbatch ──▶ compute nodes
   │                         edit, submit,                      CPU: 128 cores, 512 GB
   │                         short tests                        GPU: 64 cores + 4× A100
   ├── rsync nersc-dtn ────▶ data transfer nodes   } all of these see the same file systems:
   ├── Globus ─────────────▶ "NERSC DTN"           }  $HOME, $SCRATCH, CFS, /global/common
   └── ThinLinc ───────────▶ remote desktop (its own home; opens terminals on Perlmutter)
```

Six things to remember:

1. Your login key comes from `sshproxy` and lasts **24 hours**.
2. **Login nodes are shared:** run real work on compute nodes.
3. CPU jobs are charged to **`<project>`**, GPU jobs to **`<project>_g`**. For 1–2 GPUs, use
   the **shared** QOS; it is up to 4× cheaper than booking a whole node.
4. **`$SCRATCH` is purged** after 8 weeks without access: keep results on CFS
   (`/global/cfs/cdirs/<project>`).
5. Move data through **`nersc-dtn`** or Globus, never through the login nodes.
6. For GPU work, use the **idrobolab container**. For your own Python, use **uv**.

## Everyday commands

| Task | Command |
|---|---|
| New login key (on your laptop, daily) | `sshproxy -u <username>` |
| Log in | `ssh perlmutter` |
| Interactive 1-GPU session | `salloc -C gpu -q shared_interactive -A <project>_g -t 01:00:00 -n 1 -c 32 --gpus-per-task=1` |
| Submit / cancel a job | `sbatch job.sbatch` / `scancel <jobid>` |
| My jobs | `squeue --me` (alias `q`) or `sqs` |
| Disk usage | `showquota` |
| Hours left | <https://iris.nersc.gov> |
| Go to scratch / group project dir | `cds` / `cdp` |
| Copy to Perlmutter (on your laptop) | `rsync -azPv data/ nersc-dtn:/pscratch/sd/<x>/<username>/data/` |

## Acknowledging NERSC

Every publication (papers, theses, posters) with results computed at NERSC acknowledges
it, in the wording NERSC gives for our allocation:

> This research used resources of the National Energy Research Scientific Computing
> Center, a DOE Office of Science User Facility supported by the Office of Science of the
> U.S. Department of Energy under Contract No. DE-AC02-05CH11231 using NERSC award
> BES-ERCAP0038959.

BES-ERCAP0038959 is the award for project <project>. Source:
<https://www.nersc.gov/users/become-a-nersc-user/acknowledgement>.

## Help

- NERSC documentation: <https://docs.nersc.gov>
- NERSC tickets (account problems, lost MFA token, broken nodes): <https://help.nersc.gov>
- Outages and maintenance: <https://www.nersc.gov/live-status/motd/>
- Anything about the group setup (container, templates, Nion Swift): ask the maintainer, or open
  an issue or pull request on `idrobolab-env`.
