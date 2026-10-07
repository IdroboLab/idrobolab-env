# Delta (NCSA) — conventions

Environment setup for NCSA's Delta HPC system (Apptainer container + Slurm job
templates for another image's GPAW stack).

## Environment variables — no `$SCRATCH`

Delta defines **`$SCRATCH_BASE` (= `/scratch/<account>`, e.g. `/scratch/<project>`)
and NOT `$SCRATCH`**; the personal scratch area is `$SCRATCH_BASE/$USER`.
Any script that expands an unguarded `$SCRATCH` under `set -u` aborts.
Never emit `$SCRATCH` in Delta job scripts.

## Container image (SIF) location

Container images live in **`$PROJECTS_BASE/software/containers/`** — NOT in
scratch. Every script defaults `SIF` to
`$PROJECTS_BASE/software/containers/otherimage_delta.sif`; override per-invocation
with `SIF=/path/to/image.sif <script>`.

When adding or editing a script that references the image, use
`${PROJECTS_BASE:?set SIF, or export PROJECTS_BASE}/software/containers/otherimage_delta.sif`
as the default.

## What lives where

- **Container images** → `$PROJECTS_BASE/software/containers/` (shared, provenance
  via `sha256sum`; `*.sif` is not tracked — only the build recipes under
  `shared/containers/`).
- **Apptainer caches** → `$SCRATCH_BASE/$USER/.apptainer` (keep off `$HOME`;
  do not move to projects).
- **Source checkouts are project-scoped**: `<project-dir>/code/<name>` on
  /projects (e.g. `/projects/<project>/<username>/<campaign>/code/gpaw`),
  bound over the image's editable `/opt/src/<name>` — test code belongs to
  the campaign using it, never to a shared cross-project location. Job
  outputs and other regenerable bulk → `$SCRATCH_BASE/$USER/...`.

## Editable-install import trap — never name a dir after a package

The image installs gpaw / another image / gpaw-weaver / pyslice as **editable**
(namespace-style finder), so a directory named after one of them in your
current directory **shadows the real package**. `python -c` puts the CWD on
`sys.path`; Python then treats `./gpaw` as a namespace package, the real
`gpaw/__init__.py` never runs, and imports fail with e.g.
`cannot import name 'GPAW_NO_C_EXTENSION' from 'gpaw' (unknown location)`.

- Do not create working/output directories named `gpaw`, `otherimage`,
  `gpaw_weaver`, or `pyslice`. Branch-override checkouts go to
  `<project-dir>/code/<name>` (bound to `/opt/src/<name>`) — the `code/`
  level keeps them out of any run CWD.
- For `python -c` preflight checks, use `python -P` (drops CWD from
  `sys.path`). Never add `-P` to `python path/script.py` runs — it also
  drops the script's own dir and breaks sibling imports. Normal
  `python path/script.py` runs are immune (sys.path[0] = script dir, not CWD).
- In-container MPI must use `mpiexec -bootstrap fork` (no outer `srun`);
  without it Hydra tries the host `srun`, absent in the container. Multi-node
  uses the `srun --mpi=pmi2 apptainer exec … python` host-launcher instead.
