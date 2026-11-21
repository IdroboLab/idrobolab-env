# Release verification

An image version is released only by a merged pull request whose tests all passed on the
target clusters. This directory holds the tests, the harness that runs them, the gate that
checks the results, and the results of every release.

```
verify.py               the harness: runs the component tests of one part on one cluster
check_release.py        the gate (CI: .github/workflows/verification.yml)
test_harness.py         unit tests of both, with fake components
tests/<component>       one executable per component
clusters/<cluster>-<part>.sbatch   launchers: Perlmutter and Delta, cpu and gpu
<image>/components.tsv, known-failures.tsv
<image>/releases/<N>/   the records, logs and results table of release N
```

`verify.py`, `check_release.py` and `tests/` take the image, its clusters and its components
from `<image>/components.tsv` and the launchers. What still names this image family and is
settled at the move to hpcenv-core: the manifest fields (`lammps_ctest` in the gate and the
record), the manifest path `/opt/<image>/manifest.json`, the recipe layout
`shared/containers/<platform>/<image>/` with `VERSION`, `sources.txt`, `recipe-hash.sh` and
`requirements-<image>.txt`, and `tests/abtem`. `test_harness.py` holds the constants of the
`idrobolab` recipe at its top and also tests the recipe scripts (`recipe-hash.sh`,
`prepare_build_context.sh`, `publish.sh`, `release.sh`) and the launchers.

## The release rule

`check_release.py <image> --base <ref>` compares `VERSION` (in the image's recipe directory,
`shared/containers/*/<image>/`) with the one at `<ref>`:

- unchanged `VERSION`: the recipe hash must be unchanged, unless `VERSION` is 0 (no release yet);
- raised by exactly 1 to N: `releases/N/` must hold a complete record for every cluster and
  part that `components.tsv` requires, all of one image build (`build_id`), with the recipe
  hash and `sources.txt` of this commit, `lammps_ctest` true, and every required component
  `pass` with no unexpected failure;
- anything else fails.

It also fails, always, when a row of `components.tsv` lists no clusters or no parts, its `test`
file is missing, or it is `covered-by:<component>` of a row without a test of its own, and,
from release 1 on, when a package of `requirements-<image>.txt` has no row there. Two checks go
beyond the verification spec: every record names its own image, cluster and part, and its
`tests_hash` equals the hash of `tests/` at this commit, so tests changed after the cluster
runs invalidate the records. The image's recipe directory must be the only match of
`shared/containers/*/<image>`. The check trusts the committed
records: no CI runner has the cluster GPUs. The personal-data check over `verification/` is
the repository's `personal-data` workflow, which scans the whole tree. Run the gate locally
on the committed state:

```bash
python3 verification/check_release.py idrobolab --base origin/main
```

## Running a release on a cluster

The image `ghcr.io/idrobolab/<image>:<N>-rc` is built from the pull request branch (see the
recipe's `README.md`). Every cluster and part runs in its own allocation, from a clone on the
pull request branch, with `env.sh` sourced (its `sbatch` function adds the account):

```bash
git -C ~/idrobolab-env switch <PR branch>
sbatch ~/idrobolab-env/verification/clusters/perlmutter-cpu.sbatch idrobolab
sbatch ~/idrobolab-env/verification/clusters/perlmutter-gpu.sbatch idrobolab
sbatch ~/idrobolab-env/verification/clusters/delta-cpu.sbatch idrobolab
sbatch ~/idrobolab-env/verification/clusters/delta-gpu.sbatch idrobolab
git -C ~/idrobolab-env add verification/idrobolab/releases/<N>
```

The launchers carry the account as `<project>`. On Perlmutter `IMAGE` overrides the image: a
bare name is qualified with `IMAGE_OWNER` and `TAG` (default `<N>-rc`), a value with a `/` is
used as given. Their header comments say how to get the image onto the cluster (Perlmutter:
`update-image.sh` with `TAG=<N>-rc`, which puts a release candidate into the puller's own
`$SCRATCH/storage`; Delta: `get-image.sh` into the `.sif`). A launcher
passes everything only the host knows to `verify.py`, which runs inside the image:
`VERIFY_CLUSTER`, `VERIFY_IMAGE_DIGEST` (registry digest on Perlmutter,
`.sif` sha256 on Delta), `VERIFY_JOB_ID`, `VERIFY_WORK` (a writable directory) and
`VERIFY_SCRUB` (strings separated by `:`: user name, home, scratch and project paths, account,
the clone). `verify.py` replaces each of them by `<scrubbed>` in the record and the logs and
refuses to run when one of these variables is missing. Extra arguments go to `verify.py`: add
`--only <component>` to run one component; its record is `"complete": false` and never
satisfies the gate. The image's manifest is read from `/opt/<image>/manifest.json`
(`VERIFY_MANIFEST` overrides the path).

## Reading a record

`releases/<N>/<cluster>-<part>.json` is written by `verify.py` only, one per allocation:
the identity of the image (`version`, `build_id`, `recipe_hash`, `sources`, `lammps_ctest`,
`image_digest`), `tests_hash` (the recipe-hash construction applied to `tests/`), the cluster,
part, date, job and GPUs, `complete`, and per component:

- `status`: `pass`, `fail`, or `not-run` (excluded by `--only`);
- `passed`, `failed`, `skipped`: test counts; `failed` includes `known_failed`, the failures
  listed in `known-failures.tsv`;
- `unexpected`: the failing ids outside the list. A test that exits non-zero without a failing
  id, or reports nothing, is `exit status N` or `no test results`; a failed preflight is a
  failing test. The component fails when `unexpected` is not empty;
- `stale_known`: listed ids that passed; the gate prints them as a request to shorten the list;
- `seconds`.

`releases/<N>/<cluster>-<part>/<component>.log` holds the summary and the output of the
failing tests. `releases/<N>/README.md` is generated: one row per component, one column per
cluster and part, each cell the status and the passed / failed / skipped / known-failed counts.

## Adding a component

1. A row in `<image>/components.tsv`: `component`, `origin` (`source`, `wheel`, `system-lib`),
   `test` (a file in `tests/`, or `covered-by:<component>`), `parts` (`cpu`, `gpu`, `cpu,gpu`),
   `clusters` (comma list). A `covered-by` row is valid only when the covering test's
   preflight names the library.
2. An executable `tests/<test>` that gets `VERIFY_PART`, `VERIFY_WORK` and `VERIFY_JUNIT`
   (see `tests/abtem`). It exits 0 on success and reports either with `--junitxml=$VERIFY_JUNIT`
   or with one `PASS <id>` or `FAIL <id>` line per check. It starts with a preflight that
   prints `FAIL preflight: <what>` and exits 1 instead of skipping: the library is compiled
   in, the GPU is real (or, in the cpu part, absent), the import comes from `/opt/src` or
   `/opt/venv`.
3. A known failure goes into `<image>/known-failures.tsv` (`component`, `test id`, `cluster`
   or `*`, `part` or `*`, `reason`, `reference`: an upstream issue URL, never a private
   tracker). A junit test id is `<classname>::<name>`; copy it from a record's `unexpected`.

The unit tests: `pytest verification/test_harness.py`.
