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
