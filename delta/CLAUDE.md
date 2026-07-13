# hpcenv_delta — conventions

Environment setup for NCSA's Delta HPC system (Apptainer container + Slurm job
templates for another image's GPAW stack).

## Container image (SIF) location

Container images live in **`$PROJECTS_BASE/software/containers/`** — NOT in
`$SCRATCH/containers`. Every script defaults `SIF` to
`$PROJECTS_BASE/software/containers/otherimage_delta.sif`; override per-invocation
with `SIF=/path/to/image.sif <script>`.

When adding or editing a script that references the image, use
`${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif`
as the default.

## What lives where

- **Container images** → `$PROJECTS_BASE/software/containers/` (shared, provenance
  via `sha256sum`; `*.sif` is not tracked — only the build recipes under
  `containers/`).
- **Apptainer caches** → `$SCRATCH/.apptainer` (keep off `$HOME`; do not move to
  projects).
- **Source checkouts and job outputs** → `$SCRATCH` (e.g. `$SCRATCH/code/...`,
  benchmark output dirs). Scratch, not projects.

## Editable-install import trap — never name a dir after a package

The image installs gpaw / another image / gpaw-weaver / pyslice as **editable**
(namespace-style finder), so a directory named after one of them in your
current directory **shadows the real package**. `python -c` puts the CWD on
`sys.path`; Python then treats `./gpaw` as a namespace package, the real
`gpaw/__init__.py` never runs, and imports fail with e.g.
`cannot import name 'GPAW_NO_C_EXTENSION' from 'gpaw' (unknown location)`.

- Do not create working/output directories named `gpaw`, `otherimage`,
  `gpaw_weaver`, or `pyslice`. Branch-override checkouts go to
  `$SCRATCH/code/<name>` (bound to `/opt/src/<name>`), never in a run dir.
- For `python -c` preflight checks, use `python -P` (drops CWD from
  `sys.path`). Never add `-P` to `python path/script.py` runs — it also
  drops the script's own dir and breaks sibling imports. Normal
  `python path/script.py` runs are immune (sys.path[0] = script dir, not CWD).
- In-container MPI must use `mpiexec -bootstrap fork` (no outer `srun`);
  without it Hydra tries the host `srun`, absent in the container. Multi-node
  uses the `srun --mpi=pmi2 apptainer exec … python` host-launcher instead.
