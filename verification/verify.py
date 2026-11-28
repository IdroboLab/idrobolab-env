#!/usr/bin/env python3
"""Run the component tests of one part (cpu or gpu) of an image on the current cluster.

    python verification/verify.py <image> --part <cpu|gpu> [--only <component>]

Runs inside the image, started by a launcher in clusters/, which passes what only the host
knows: VERIFY_CLUSTER, VERIFY_IMAGE_DIGEST, VERIFY_JOB_ID, VERIFY_WORK (a writable directory)
and VERIFY_SCRUB (strings to remove from everything written, separated by `:`). The image's
manifest is /opt/<image>/manifest.json (VERIFY_MANIFEST overrides the path).

For every row of <image>/components.tsv that lists this cluster and part, it runs
tests/<test> with VERIFY_PART, VERIFY_WORK (a directory of its own) and VERIFY_JUNIT. A test
reports through the junit file it writes, else through the `PASS <id>` and `FAIL <id>` lines
it prints. A junit test id is `<classname>::<name>`. A failing id that is not in
known-failures.tsv (for this component, cluster and part, `*` matching any) is unexpected; a
listed id that passed is stale. The `test id`s of the rows of deselected.tsv that match the
component, cluster and part in the same way go to the test as VERIFY_DESELECT, one per line,
for it to leave out (each test says how), and into the record's `deselected`. A test that
exits non-zero for no failing id, or has no passing test (all skipped, or nothing reported),
fails with the id `exit status N` or `no test results`; a test file that cannot be run fails
with exit status 127. Nothing is skipped silently.

VERIFY_DEADLINE (epoch seconds, the job's end time, set by the launchers) gives each component
a timeout of the time left minus DEADLINE_MARGIN. A component runs in a process group of its own;
a timeout kills the group (the output is collected for at most KILL_GRACE seconds more) and fails
the component with `timeout after N s`. Every later component is `not-run`, as is one that would
start inside the margin, and the record is incomplete. A VERIFY_DEADLINE that is unset, empty,
not an integer or past means no timeout, with a warning.

Writes <image>/releases/<version>/<cluster>-<part>.json (the record), the logs under
<cluster>-<part>/, and the generated README.md of that release. Every VERIFY_SCRUB string is
replaced by `<scrubbed>` in all of them. `--only` marks the record incomplete; the other
components get the status `not-run`. Exit status: 0 when every selected component passed.
Python standard library only.
"""
import argparse
import csv
import datetime
import json
import os
import re
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
LAUNCHER_ENV = ("VERIFY_CLUSTER", "VERIFY_IMAGE_DIGEST", "VERIFY_JOB_ID", "VERIFY_SCRUB",
                "VERIFY_WORK")
MAX_FAILURE_TEXT = 2000
DEADLINE_MARGIN = 900  # seconds kept for writing the record and the launcher's cleanup
KILL_GRACE = 30  # seconds to collect the output of a killed component


def read_tsv(path):
    with open(path, newline="") as f:
        return list(csv.DictReader((line for line in f if not line.startswith("#")),
                                   delimiter="\t"))


def items(value):
    return [x.strip() for x in value.split(",") if x.strip()]


def own_components(image):
    """The rows of components.tsv that have a test of their own (not `covered-by:`)."""
    rows = read_tsv(HERE / image / "components.tsv")
    return [r for r in rows if not r["test"].startswith("covered-by:")]


def recipe_dir(image):
    """The image's recipe directory: shared/containers/<platform>/<image>, exactly one."""
    found = sorted(ROOT.glob(f"shared/containers/*/{image}"))
    if len(found) != 1:
        sys.exit(f"{image}: exactly one recipe directory shared/containers/*/{image} is "
                 f"expected, found {len(found)}")
    return found[0]


def recipe_hash(image, directory):
    """The recipe-hash construction of the image's recipe, applied to `directory`."""
    return subprocess.run([recipe_dir(image) / "recipe-hash.sh", directory], check=True,
                          capture_output=True, text=True).stdout.strip()


def parse_junit(path):
    passed, failures, skipped = [], {}, 0
    for case in ET.parse(path).iter("testcase"):
        name = case.get("name", "")
        tid = f"{case.get('classname')}::{name}" if case.get("classname") else name
        bad = next((e for e in case if e.tag in ("failure", "error")), None)
        if bad is not None:
            failures[tid] = f"{bad.get('message') or ''}\n{bad.text or ''}"
        elif case.find("skipped") is not None:
            skipped += 1
        else:
            passed.append(tid)
    return passed, failures, skipped


def parse_lines(output):
    passed, failures = [], {}
    for line in output.splitlines():
        m = re.fullmatch(r"(PASS|FAIL) (.+)", line)
        if m and m.group(1) == "PASS":
            passed.append(m.group(2))
        elif m:
            failures[m.group(2)] = line
    return passed, failures, 0


def read_deadline():
    """The job's end time (epoch seconds) from VERIFY_DEADLINE, or None, with a warning, when
    it is unset, empty, not an integer or already past."""
    value = os.environ.get("VERIFY_DEADLINE", "")
    try:
        deadline = int(value)
    except ValueError:
        deadline = 0
    if deadline <= time.time():
        print(f"verify.py: VERIFY_DEADLINE={value!r} is not a future time in epoch seconds: "
              "no component timeout", file=sys.stderr)
        return None
    return deadline


def kill_group(proc):
    """Kill the process group of `proc`; return its output. Each wait is bounded by KILL_GRACE,
    so a process outside the group that holds the pipe, or a leader in uninterruptible sleep
    that defers the kill, cannot block the record."""
    os.killpg(proc.pid, signal.SIGKILL)
    try:
        output, _ = proc.communicate(timeout=KILL_GRACE)
    except subprocess.TimeoutExpired as e:
        output = e.output or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        proc.stdout.close()
    try:
        proc.wait(timeout=KILL_GRACE)
    except subprocess.TimeoutExpired:
        pass
    return output


def matching(rows, comp, cluster, part):
    """The `test id`s of the rows of a known-failures.tsv or deselected.tsv that apply to the
    component in this part on this cluster (`*` matches any)."""
    return [k["test id"] for k in rows if k["component"] == comp
            and k["cluster"] in (cluster, "*") and k["part"] in (part, "*")]


def run_component(row, part, cluster, known, work, timeout=None, deselected=()):
    """Run one component test, in a process group of its own that is killed after `timeout`
    seconds, with the matching rows of `deselected` in VERIFY_DESELECT; return its record
    entry, its log text and whether it timed out."""
    comp = row["component"]
    deselect = matching(deselected, comp, cluster, part)
    cwork = work / comp
    cwork.mkdir(parents=True, exist_ok=True)
    junit = cwork / "junit.xml"
    junit.unlink(missing_ok=True)
    env = {**os.environ, "VERIFY_PART": part, "VERIFY_WORK": str(cwork),
           "VERIFY_JUNIT": str(junit), "VERIFY_DESELECT": "\n".join(deselect)}
    start = time.monotonic()
    command = [HERE / "tests" / row["test"]]
    timed_out = False
    try:
        proc = subprocess.Popen(command, env=env, cwd=cwork, text=True, errors="replace",
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                start_new_session=True)
    except OSError as e:  # missing or not executable
        returncode, output = 127, f"cannot run {command[0]}: {e}\n"
    else:
        try:
            output, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:  # mpiexec and the xdist workers are children
            output = kill_group(proc)
            timed_out = True
        returncode = proc.returncode
    seconds = round(time.monotonic() - start)
    passed, failures, skipped = (parse_junit(junit) if junit.exists()
                                 else parse_lines(output))

    listed = set(matching(known, comp, cluster, part))
    known_failed = [t for t in failures if t in listed]
    unexpected = [t for t in failures if t not in listed]
    if timed_out:
        unexpected.append(f"timeout after {round(timeout)} s")
    elif not failures and returncode != 0:
        unexpected.append(f"exit status {returncode}")
    if not passed and not unexpected:
        unexpected.append("no test results")
    entry = {"status": "fail" if unexpected else "pass", "passed": len(passed),
             "failed": len(known_failed) + len(unexpected), "skipped": skipped,
             "known_failed": len(known_failed), "unexpected": unexpected,
             "stale_known": [t for t in passed if t in listed], "deselected": deselect,
             "seconds": seconds}

    log = [f"component {comp}, part {part}, cluster {cluster}",
           f"status {entry['status']}: {entry['passed']} passed, {entry['failed']} failed "
           f"({entry['known_failed']} known), {skipped} skipped, exit status "
           f"{returncode}, {seconds} s"]
    log += [f"unexpected: {t}" for t in unexpected]
    log += [f"stale known failure: {t}" for t in entry["stale_known"]]
    log += [f"deselected: {t}" for t in deselect]
    for tid, text in failures.items():
        log += ["", f"--- failing: {tid}", text[:MAX_FAILURE_TEXT]]
    if unexpected and (timed_out or not failures):
        log += ["", "--- last lines of output", *output.splitlines()[-60:]]
    return entry, "\n".join(log) + "\n", timed_out


def gpu_description():
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                             check=True, capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return "none"
    return ", ".join(f"{n}x {name}" for name, n in Counter(out.splitlines()).items()) or "none"


def write_readme(image, release_dir):
    records = {p.stem: json.loads(p.read_text()) for p in sorted(release_dir.glob("*.json"))}
    components = list(dict.fromkeys(c for r in records.values() for c in r["components"]))
    heads = [name + ("" if r["complete"] else " (incomplete)") for name, r in records.items()]
    lines = [f"# {image} {release_dir.name}: verification results", "",
             "Generated by `verify.py`; do not edit. Rows: components. Columns: cluster and "
             "part. Cell: the status, then the passed / failed / skipped / known-failed counts "
             "of the component in that part on that cluster; `-` where the part does not test "
             "it.", "", "| component | " + " | ".join(heads) + " |",
             "|---" * (len(heads) + 1) + "|"]
    for comp in components:
        cells = []
        for r in records.values():
            e = r["components"].get(comp)
            cells.append("-" if e is None else e["status"] if e["status"] == "not-run" else
                         f"{e['status']} {e['passed']} / {e['failed']} / {e['skipped']} / "
                         f"{e['known_failed']}")
        lines.append(f"| {comp} | " + " | ".join(cells) + " |")
    (release_dir / "README.md").write_text("\n".join(lines) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image")
    ap.add_argument("--part", choices=("cpu", "gpu"), required=True)
    ap.add_argument("--only", help="run one component and mark the record incomplete")
    args = ap.parse_args(argv)
    missing = [v for v in LAUNCHER_ENV if not os.environ.get(v)]
    if missing:
        sys.exit("verify.py: the launcher sets " + ", ".join(missing))
    cluster, part = os.environ["VERIFY_CLUSTER"], args.part
    recipe_dir(args.image)
    scrub = sorted(filter(None, os.environ["VERIFY_SCRUB"].split(":")), key=len, reverse=True)

    def scrubbed(value):
        """Text, or the string values of a JSON structure, without the scrub strings."""
        if isinstance(value, dict):
            return {k: scrubbed(v) for k, v in value.items()}
        if isinstance(value, list):
            return [scrubbed(v) for v in value]
        if isinstance(value, str):
            for s in scrub:
                value = value.replace(s, "<scrubbed>")
        return value

    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    manifest = json.loads(Path(os.environ.get(
        "VERIFY_MANIFEST", f"/opt/{args.image}/manifest.json")).read_text())
    rows = [r for r in own_components(args.image)
            if cluster in items(r["clusters"]) and part in items(r["parts"])]
    if args.only and args.only not in [r["component"] for r in rows]:
        sys.exit(f"verify.py: no component {args.only} in the {cluster} {part} part")
    known = read_tsv(HERE / args.image / "known-failures.tsv")
    deselected = read_tsv(HERE / args.image / "deselected.tsv")
    tests_hash = recipe_hash(args.image, HERE / "tests")  # before the tests: it needs git

    release_dir = HERE / args.image / "releases" / str(manifest["version"])
    log_dir = release_dir / f"{cluster}-{part}"
    log_dir.mkdir(parents=True, exist_ok=True)
    deadline = read_deadline()
    results, out_of_time = {}, False  # a component timed out, or the margin is reached
    for row in rows:
        comp = row["component"]
        selected = not args.only or comp == args.only
        remaining = None if deadline is None else deadline - time.time() - DEADLINE_MARGIN
        out_of_time = out_of_time or selected and remaining is not None and remaining <= 0
        if not selected or out_of_time:
            results[comp] = {"status": "not-run", "passed": 0, "failed": 0, "skipped": 0,
                             "known_failed": 0, "unexpected": [], "stale_known": [],
                             "deselected": [], "seconds": 0}
            continue
        results[comp], log, out_of_time = run_component(
            row, part, cluster, known, Path(os.environ["VERIFY_WORK"]), remaining, deselected)
        (log_dir / f"{comp}.log").write_text(scrubbed(log))

    record = {"image": args.image, "version": manifest["version"],
              "build_id": manifest["build_id"], "recipe_hash": manifest["recipe_hash"],
              "sources": manifest["sources"], "lammps_ctest": manifest["lammps_ctest"],
              "image_digest": os.environ["VERIFY_IMAGE_DIGEST"],
              "tests_hash": tests_hash, "cluster": cluster,
              "part": part, "date_utc": today,
              "job_id": os.environ["VERIFY_JOB_ID"],
              "gpu": gpu_description() if part == "gpu" else "none",
              "complete": not args.only and not out_of_time,
              "components": results}
    (release_dir / f"{cluster}-{part}.json").write_text(
        json.dumps(scrubbed(record), indent=1) + "\n")
    write_readme(args.image, release_dir)
    bad = [c for c, r in results.items() if r["status"] == "fail"]
    not_run = sum(r["status"] == "not-run" for r in results.values())
    passed = sum(r["status"] == "pass" for r in results.values())
    print(f"{cluster}-{part}: {passed} of {len(results)} components passed"
          + (f"; failed: {', '.join(bad)}" if bad else "")
          + (f"; {not_run} not run" if not_run else "")
          + ("; stopped at the deadline" if out_of_time else ""))
    return 1 if bad or out_of_time else 0


if __name__ == "__main__":
    sys.exit(main())
