# IdroboLab group rules (NERSC project <project>)

These rules add to NERSC's guidance above and never relax it. Details are in the
group's Perlmutter pages, `~/idrobolab-env/docs/perlmutter/` (clone path may differ).

## Jobs

- Accounts: `-A <project>` for CPU jobs, `-A <project>_g` for GPU jobs.
- 1 or 2 GPUs go to the `shared` / `shared_interactive` QOS, with the CPU count given
  explicitly: `-c 32` for 1 GPU, `-c 64` for 2. Whole nodes (`interactive`, `regular`)
  only for work that uses all four GPUs. See `04-jobs.md`.
- Before every allocation (`salloc`, `sbatch`, `srun` outside one), state the account,
  QOS, number of GPUs and time limit, and wait for the user's approval. Use a realistic
  time limit; end interactive sessions when done, because idle time is charged.

## Software

- GPU and simulation work runs in the idrobolab container; the alternative is the user's
  own uv environment. `06-containers.md`, `07-abtem.md`, `05-python-uv.md`.
- Never install anything into `/global/common/software/<project>`, pull container images
  or run `uv self update`: the maintainer does that.
- Python scripts carry their dependencies in a PEP 723 header and run with
  `uv run --script`.

## Data

- Run and write output in `$SCRATCH`; results to keep go to
  `/global/cfs/cdirs/<project>/projects/<project>/` when the user asks. Write CFS paths
  as `/global/cfs/cdirs/...`.
- Never delete, move, overwrite or change the permissions of files on CFS that the user
  does not own.
- Unpublished data and collaborators' data stay private: do not send them to external
  services, and ask the user before reading a collaborator's data.
- Scripts that write atomic structures (extxyz, traj, POSCAR, ...) also write a `.cif`.

## Provenance

Keep the job script, its output, the image digest (`podman-hpc images --digests |
grep idrobolab`) and, for a package run from the user's own checkout, its commit
(`git -C <checkout> rev-parse HEAD`) together with the results. `docs/perlmutter/conventions.md`.
