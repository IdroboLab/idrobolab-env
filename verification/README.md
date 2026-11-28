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
<image>/components.tsv, known-failures.tsv, deselected.tsv
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
file is missing, or it is `covered-by:<component>` of a row without a test of its own or of a
test whose preflight does not name the row's component (*Naming a covered library*), and,
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
(`VERIFY_MANIFEST` overrides the path). On Delta the image's writable layer, where the tests
install their dependencies into `/opt/venv`, is a 2 GB overlay image in the work directory:
`--writable-tmpfs` gives only 64 MiB there, too little for abTEM's and GPAW's installs.

Each launcher also exports `VERIFY_DEADLINE`, the job's end time in epoch seconds
(`squeue -h -j $SLURM_JOB_ID -o %e`, converted with `date -d`; Perlmutter passes it into the
container with `-e`). When squeue or date fails, nothing is exported. `verify.py` gives each
component a timeout of the time left until the deadline minus 15 minutes, which it keeps for
writing the record and the launcher's cleanup. A component runs in a process group of its own,
and a timeout kills the whole group (mpiexec and the xdist workers are children). The component
then fails with `unexpected: ["timeout after N s"]` and the last 60 lines of its output in its
log (collected for at most 30 s after the kill, so a process outside the group that holds the
pipe cannot block the record). Every later component is `not-run`, as is one that would start
inside the 15 minutes, and the record is `"complete": false` (the gate rejects it), written
together with the README. A `VERIFY_DEADLINE` that is unset, empty, not an
integer or already past means no timeout, with one warning line.

The CPU launchers allocate two nodes. Before `verify.py`, which runs on one node as for the
other parts, they run the 2-node MPICH step: a ring of one rank per node over the fabric (`tests/mpich --ring --ranks 2`, in the
container, started by the host's `srun`). On Perlmutter that is `podman-hpc run --mpi`, which
swaps the host's Cray MPICH in for the image's (ABI-compatible `libmpi.so.12`) as production
jobs launch, so it tests the image's MPI-ABI binaries over the fabric with the host MPICH; on
Delta it is `srun --mpi=pmi2 apptainer exec` with the image's own MPICH, which tests that
MPICH. The step writes its exit status and log into `$WORK/mpi-step`, `VERIFY_MPI_STEP` names
that directory for `tests/mpich`, and a failed step is recorded there and does not stop the
job: `tests/mpich` then fails the component. A step that hangs ends after `MPI_STEP_TIMEOUT`
seconds (default 600) with status 124. The step's output also goes to the job's output file,
because `$WORK` is removed at the end. After the step the launchers shrink the job to its first
node (`scontrol update NumNodes=1`), so the second is not billed while `verify.py` runs. Delta
refuses the shrink ("Job is no longer pending execution") for a job submitted with
`--ntasks-per-node`, so their headers set none; a refused shrink prints a warning and the job
goes on with both nodes. The GPU launchers stay on one node.

The time limit of the CPU launchers (4 h) is a guess: GPAW's full suite (`tests/gpaw`) is the
longest component (its np4 phase runs in concurrent groups, below). Override it at
submission: `sbatch --time=12:00:00 <launcher> <image>`.

## Reading a record

`releases/<N>/<cluster>-<part>.json` is written by `verify.py` only, one per allocation:
the identity of the image (`version`, `build_id`, `recipe_hash`, `sources`, `lammps_ctest`,
`image_digest`), `tests_hash` (the recipe-hash construction applied to `tests/`), the cluster,
part, date, job and GPUs, `complete`, and per component:

- `status`: `pass`, `fail`, or `not-run` (excluded by `--only`, or after a component
  that timed out);
- `passed`, `failed`, `skipped`: test counts; `failed` includes `known_failed`, the failures
  listed in `known-failures.tsv`;
- `unexpected`: the failing ids outside the list. A test that exits non-zero without a failing
  id, or reports nothing, is `exit status N` or `no test results`; one that runs into the
  job's deadline is `timeout after N s`; a failed preflight is a failing test. The component
  fails when `unexpected` is not empty;
- `stale_known`: listed ids that passed; the gate prints them as a request to shorten the list;
- `deselected`: the `test id`s of the matching rows of `deselected.tsv`, which `verify.py`
  passed to the test as `VERIFY_DESELECT` and which therefore did not run;
- `seconds`.

`releases/<N>/<cluster>-<part>/<component>.log` holds the summary and the output of the
failing tests. `releases/<N>/README.md` is generated: one row per component, one column per
cluster and part, each cell the status and the passed / failed / skipped / known-failed counts.

## Adding a component

1. A row in `<image>/components.tsv`: `component`, `origin` (`source`, `wheel`, `system-lib`),
   `test` (a file in `tests/`, or `covered-by:<component>`), `parts` (`cpu`, `gpu`, `cpu,gpu`),
   `clusters` (comma list). A `covered-by` row is valid only when the covering test's
   preflight names the library (*Naming a covered library*).
2. An executable `tests/<test>` that gets `VERIFY_PART`, `VERIFY_WORK`, `VERIFY_JUNIT` and
   `VERIFY_DESELECT` (see `tests/abtem`; only a test that says it reads `VERIFY_DESELECT`,
   today `tests/gpaw`, leaves its ids out). It exits 0 on success and reports either with
   `--junitxml=$VERIFY_JUNIT` or with one `PASS <id>` or `FAIL <id>` line per check. It
   starts with a preflight that prints `FAIL preflight: <what>` and exits 1 instead of
   skipping: the library is compiled in, the GPU is real (or, in the cpu part, absent), the
   import comes from `/opt/src` or `/opt/venv`.
3. A known failure goes into `<image>/known-failures.tsv` (`component`, `test id`, `cluster`
   or `*`, `part` or `*`, `reason`, `reference`: an upstream issue or merge-request URL,
   never a private tracker). A junit test id is `<classname>::<name>`; copy it from a record's
   `unexpected`. A test that cannot run at all, because it hangs the run instead of failing,
   goes into `<image>/deselected.tsv` (same columns; every image has the file, with at least
   its header line). Its `test id` is what the component test deselects (for `tests/gpaw`, a
   pytest node id deselected in the np4 phase), one per line in `VERIFY_DESELECT`. A row for
   a component whose test does not read `VERIFY_DESELECT` would be recorded as deselected
   although the test ran.

The unit tests: `pytest verification/test_harness.py`.

## Naming a covered library

A system library without a test of its own is `covered-by:<component>`, and the covering test's
preflight must check it: a green upstream suite can hide that a library is absent, because the
tests that need it skip. The test declares the libraries its preflight checks as a module-level
tuple of string literals, `PREFLIGHT_LIBRARIES = ("scalapack", "fftw", ...)`, and its preflight
iterates over that tuple (`tests/gpaw`). `check_release.py` reads the tuple with `ast`, without
importing the test (no gpaw in the gate), and fails a `covered-by` row whose component name
(compared lower-case, `_` as `-`) is not in it, or whose covering test declares none.

## GPAW and MPI tests

Each test's docstring says what it runs; this lists what is not obvious from it.

- `tests/gpaw`: GPAW's full suite with plain `python -m pytest`, not
  `shared/testing/run_pytest.py`: GPAW's conftest uses pytest's cache (`config.cache`), which
  `run_pytest.py` disables with `-p no:cacheprovider`, so the suite uses `-o cache_dir`
  instead. Tests of an absent optional library skip, so its preflight checks the libraries
  through GPAW's own build information. `verify.py` keeps pytest's output (`-rs` skip reasons
  included) only for a failing run that reports no failing test. The cpu part runs three
  phases: the precalc and serial phases with `pytest -n 32`, and np4, the whole suite under
  `mpiexec -n 4`, split into `NP4_GROUPS` groups with pytest-test-groups (the plugin and
  seed 42 of GPAW's own nightly CI). All groups run at once, each with a `TMPDIR` of its own
  and one junit file per rank (`np4-g<i>-rank<r>.xml`); the merged record keeps rank 0 of each
  group in full and only the failing cases of the other ranks (classname prefixes `np4.` and
  `np4-rank<r>.`). A group that wrote no rank-0 file (killed by its timeout or the OOM killer)
  is a failing case `group <i> wrote no junit (exit status N)`, carrying the last lines of the
  group's output (`np4-g<i>.log`), which a failing group also prints; a group still running
  `NP4_GROUP_TIMEOUT` seconds after the start is ended that way, since a test failing on some
  ranks leaves the others blocked in a collective, out of pytest-timeout's reach. The node ids
  in `VERIFY_DESELECT` (from `deselected.tsv`) are deselected in the np4 phase only; the serial
  phase still runs them. The worst
  exit status counts, a death by signal as a failure. Every pytest run has
  `--timeout=<TEST_TIMEOUT> --timeout-method=thread` (pytest-timeout): a hung test fails with a
  stack dump, and under MPI that rank's exit ends its group. OMP, OPENBLAS and MKL threads are
  pinned to 1 per process, as up to 32 processes share the node. A run that still overruns the
  job ends at `VERIFY_DEADLINE`, above. The cpu part sets `GPAW_CPUPY=1`, GPAW's CuPy
  emulation for `gpu=True` calculations outside pytest (GPAW's conftest already allows them in
  its sessions).
- `tests/gpaw-eigensolvers`: ScaLAPACK against ELPA total energies, and which solver each run
  used.
- `tests/gpaw-weaver`: gpaw-weaver's own suite and a real GPAW run of its entry point. Its SCF
  history cases fail with the log formats of the image's GPAW until gpaw-weaver's parser reads
  them, or `known-failures.tsv` lists them.
- `tests/gpaw-data`: the PAW setups of the gpaw-data wheel.
- `tests/mpich`: the in-container ring and the result of the 2-node step above.

The test scripts share `tests/_common.py`, which is not a component: it has no row, is covered
by `tests_hash` like every file in `tests/`, and is imported from the script's own directory
(not under `PYTHONSAFEPATH=1`).
