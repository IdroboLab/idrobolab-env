# Group conventions (draft)

How we work on Perlmutter as a group. This is a **first draft**, collected from what we
already do; it will change. Propose changes with a pull request
([page 2](02-github.md#6-everyday-git)), and raise the open points below at the next
group meeting.

## Settings and code

- Everyone works in their **own clone** of `idrobolab-env` at `~/idrobolab-env`, with
  the group setup sourced from it ([page 3](03-shell-setup.md)). Changes go through a
  branch and a pull request, not straight to `main`.
- Shared software is installed by the maintainer: the container image, the shared
  Python interpreters and `uv`, the Nion Swift install, the shared Jupyter kernels.
  Don't pull images, run `uv self update`, or install into
  `/global/common/software/<project>` yourself. Ask instead.
- Your own code lives in git repositories (yours or IdroboLab's), not only on
  Perlmutter.

## Data

- **Run in `$SCRATCH`, keep on CFS, archive to HPSS.** Scratch is purged after 8 weeks
  without access.
- Group data lives in `/global/cfs/cdirs/<project>/projects/<project>/`. Use one folder per
  project; agree on the name with the people involved.
- Keep shared folders **group-readable** (`chmod -R g+rX <folder>`).
- **Never delete, move, overwrite or change the permissions of someone else's files**,
  even where the file system lets you. Ask the owner (`ls -l` shows who).
- Write CFS paths as `/global/cfs/cdirs/...` (containers don't see the `projectdirs`
  name).
- Big transfers go through `nersc-dtn` or Globus, never the login nodes.

## Compute

- CPU jobs: `-A <project>`. GPU jobs: `-A <project>_g`.
- **1–2 GPUs → `shared` / `shared_interactive`.** Book whole nodes only for work that
  uses all four GPUs.
- Give every job a realistic time limit, and test a new job script with a short run
  first.
- End interactive sessions, Jupyter servers and Nion Swift when you're done: idle time
  is charged.
- Nothing heavy on the login nodes, for you and for any coding agent you run
  ([page 10](10-coding-agents.md)).

## Software and provenance

- GPU and simulation work runs in the **idrobolab container**
  ([page 7](07-containers.md)). Your own analysis environments use **uv**
  ([page 6](06-python-uv.md)).
- **Record what produced a result:** keep the job script, its output file and the
  image digest (`podman-hpc images --digests | grep idrobolab`) with the results. When
  you use your own checkout of a package (e.g. abTEM), record its commit too
  (`git -C <checkout> rev-parse HEAD`).
- Python scripts carry their dependencies in a PEP 723 header and run with
  `uv run --script` ([page 6](06-python-uv.md#three-ways-to-use-it)).
- Scripts that write atomic structures (extxyz, traj, POSCAR, …) also write a `.cif`,
  so the structure can be checked in VESTA.

## Publications

Acknowledge NERSC in every paper that used Perlmutter
([wording](README.md#acknowledging-nersc)).

## Open points

- Folder layout inside a project directory (raw data, simulations, analysis, figures)
  and naming.
- How raw microscope data gets from the instruments to CFS (Globus Connect Personal on
  the acquisition PC?), and who may delete it.
- Above what size a campaign is announced to the group before it is submitted, since
  hours come from one shared allocation.
- When finished projects move to HPSS, and who does it.
