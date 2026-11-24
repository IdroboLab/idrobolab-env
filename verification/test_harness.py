"""Tests of the version identity of the idrobolab recipe (recipe-hash.sh,
prepare_build_context.sh, publish.sh and release.sh), run in a temporary copy of the recipe's
scripts with temporary source repositories (a bare origin and a clone each) and a stub
container engine that only logs its calls, so nothing touches the network, a registry or a
credential, and nothing depends on a local checkout of the sources; and of the harness
verify.py and the gate check_release.py, run in a temporary git repository with fake
components, a fake manifest and hand-written records; and of check-no-avx512.sh, run on objects
assembled from single instructions.
Run: pytest verification/test_harness.py"""
import copy
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

# Everything specific to the idrobolab recipe is here.
IMAGE = "idrobolab"
REGISTRY_IMAGE = "ghcr.io/idrobolab/idrobolab"
RECIPE_REL = Path("shared/containers/x86_64-cuda/idrobolab")
SELFTEST_REL = Path("core/lammps/lammps-gpu-selftest.sh")  # staged into the recipe dir
STAGED = "lammps-gpu-selftest.sh"
HASH_SCRIPT = "recipe-hash.sh"
PREPARE_SCRIPT = "prepare_build_context.sh"
PUBLISH_SCRIPT = "publish.sh"
RELEASE_SCRIPT = "release.sh"
SCRIPTS = (HASH_SCRIPT, PREPARE_SCRIPT, PUBLISH_SCRIPT, RELEASE_SCRIPT)
TREES = ("gpaw", "gpaw-weaver", "abTEM")
RELEASES_REL = Path("verification") / IMAGE / "releases"
VERSION = 3
REQUIREMENTS = f"requirements-{IMAGE}.txt"
ABTEM = "abtem"  # the component whose test script is exercised itself
LAUNCHERS = [f"{c}-{p}.sbatch" for c in ("perlmutter", "delta") for p in ("cpu", "gpu")]

STUB_ENGINE = """#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
    "pull -q") [[ "$3" != *-rc-sources ]] || exit "${STUB_SOURCES_RC:-0}" ;;
    "manifest inspect") printf '%s\\n' "${STUB_MANIFEST_OUT:-}"; exit "${STUB_MANIFEST_RC:-1}" ;;
    "image inspect") case "$*" in *Labels*) echo "${STUB_LABEL:-}" ;; *) echo "${STUB_DIGEST:-sha256:aa}" ;; esac ;;
    "login "*) cat > /dev/null ;;
esac
"""


def git(cwd, *args):
    out = subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
        cwd=cwd, check=True, capture_output=True, text=True)
    return out.stdout.strip()


@pytest.fixture
def recipe(tmp_path):
    """A git repository with the recipe layout, one commit, and a clean recipe directory."""
    repo = tmp_path / "env"
    d = repo / RECIPE_REL
    d.mkdir(parents=True)
    for name in SCRIPTS:
        shutil.copy(ROOT / RECIPE_REL / name, d / name)
    (d / "VERSION").write_text(f"{VERSION}\n")
    (d / "README.md").write_text("docs\n")
    (d / "Dockerfile").write_text("FROM scratch\n")
    (repo / ".gitignore").write_text(f"src/\n{STAGED}\n")
    (repo / SELFTEST_REL).parent.mkdir(parents=True)
    (repo / SELFTEST_REL).write_text("#!/bin/sh\n")
    git(repo, "init", "-q")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "recipe")
    return d


def repo_root(d):
    return d.parents[len(RECIPE_REL.parts) - 1]


def recipe_hash(d):
    return subprocess.run([d / HASH_SCRIPT], check=True, capture_output=True,
                          text=True).stdout.strip()


def commit_all(d, msg):
    git(d, "add", "-A", ".")
    git(d, "commit", "-qm", msg)


def test_recipe_hash_is_equal_for_equal_trees(recipe, tmp_path):
    other = tmp_path / "copy"
    shutil.copytree(repo_root(recipe), other)
    h = recipe_hash(recipe)
    assert re.fullmatch(r"[0-9a-f]{64}", h)
    assert recipe_hash(other / RECIPE_REL) == h


def test_recipe_hash_is_the_sha256_of_the_repo_relative_index_listing(recipe):
    listing = git(repo_root(recipe), "ls-files", "-s", "--", str(RECIPE_REL))
    listing = "".join(line + "\n" for line in listing.splitlines()
                      if not line.endswith(f"\t{RECIPE_REL}/README.md"))
    want = subprocess.run(["sha256sum"], input=listing, capture_output=True,
                          text=True).stdout.split()[0]
    assert recipe_hash(recipe) == want


def test_recipe_hash_ignores_readme_only(recipe):
    h = recipe_hash(recipe)
    (recipe / "README.md").write_text("other docs\n")
    commit_all(recipe, "readme")
    assert recipe_hash(recipe) == h
    (recipe / "Dockerfile").write_text("FROM scratch\nRUN true\n")
    commit_all(recipe, "dockerfile")
    assert recipe_hash(recipe) not in (h, "dirty")


@pytest.mark.parametrize("change", ["edit", "readme", "new file", "staged"])
def test_recipe_hash_is_dirty_with_an_uncommitted_change(recipe, change):
    if change == "edit":
        (recipe / "Dockerfile").write_text("changed\n")
    elif change == "readme":
        (recipe / "README.md").write_text("changed\n")
    else:
        (recipe / "new.txt").write_text("x\n")
        if change == "staged":
            git(recipe, "add", "new.txt")
    assert recipe_hash(recipe) == "dirty"


def test_recipe_hash_ignores_staged_build_inputs(recipe):
    (recipe / "src").mkdir()
    (recipe / "src/x").write_text("x\n")
    (recipe / STAGED).write_text("#!/bin/sh\n")
    assert recipe_hash(recipe) != "dirty"


@pytest.fixture
def code_dir(tmp_path):
    """One clone of a bare origin per tree, with two pushed commits."""
    code = tmp_path / "code"
    for name in TREES:
        origin = tmp_path / f"{name}.git"
        git(tmp_path, "init", "-q", "--bare", "-b", "main", str(origin))
        clone = code / name
        git(tmp_path, "clone", "-q", str(origin), str(clone))
        for i in (1, 2):
            (clone / f"{name}_{i}.py").write_text(f"{i}\n")
            (clone / "pkg").mkdir(exist_ok=True)
            (clone / "pkg/mod.py").write_text(f"{name} {i}\n")
            git(clone, "add", "-A")
            git(clone, "commit", "-qm", f"c{i}")
        git(clone, "push", "-q", "-u", "origin", "main")
    return code


def pins(code, rev="HEAD"):
    return {n: git(code / n, "rev-parse", rev) for n in TREES}


def run_script(recipe, script, tmp_path, **env):
    """Run a recipe script with the stub engine; the log of its calls is tmp_path/engine.log."""
    stub = tmp_path / "engine"
    stub.write_text(STUB_ENGINE)
    stub.chmod(0o755)
    full = {"PATH": os.environ["PATH"], "ENGINE": str(stub), "STUB_LOG": str(tmp_path / "engine.log"),
            "GHCR_USER": "dummy-user", "GITHUB_PACKAGE_TOKEN": "dummy-token"}
    full.update({k: str(v) for k, v in env.items()})
    return subprocess.run([recipe / script], env=full, capture_output=True, text=True)


def engine_calls(tmp_path, verb=""):
    log = tmp_path / "engine.log"
    lines = log.read_text().splitlines() if log.exists() else []
    return [line for line in lines if line.startswith(verb)]


def prepare(recipe, code, pin, tmp_path):
    (recipe / "sources.txt").write_text("".join(f"{n} {s}\n" for n, s in pin.items()))
    commit_all(recipe, "sources")
    return run_script(recipe, PREPARE_SCRIPT, tmp_path, CODE_DIR=code)


def test_prepare_stages_the_pinned_commits_and_writes_the_manifest(recipe, code_dir, tmp_path):
    pin = pins(code_dir, "HEAD~1")  # not the head: the pin decides
    res = prepare(recipe, code_dir, pin, tmp_path)
    assert res.returncode == 0, res.stderr
    for name, sha in pin.items():
        want = tmp_path / f"archive-{name}"
        want.mkdir()
        archive = subprocess.run(["git", "-C", code_dir / name, "archive", sha], check=True,
                                 capture_output=True).stdout
        subprocess.run(["tar", "-xf", "-", "-C", want], input=archive, check=True)
        subprocess.run(["diff", "-r", want, recipe / "src" / name], check=True)
    m = json.loads((recipe / "src/manifest.json").read_text())
    assert m["image"] == IMAGE
    assert m["version"] == VERSION
    assert m["recipe_hash"] == recipe_hash(recipe)
    assert re.fullmatch(r"\d{8}T\d{6}Z", m["build_id"])
    assert m["sources"] == pin


def test_prepare_reads_a_last_line_without_a_newline(recipe, code_dir, tmp_path):
    pin = pins(code_dir)
    (recipe / "sources.txt").write_text("\n".join(f"{n} {s}" for n, s in pin.items()))
    commit_all(recipe, "sources")
    assert run_script(recipe, PREPARE_SCRIPT, tmp_path, CODE_DIR=code_dir).returncode == 0
    assert json.loads((recipe / "src/manifest.json").read_text())["sources"] == pin


def test_prepare_fails_on_a_sources_file_without_entries(recipe, code_dir, tmp_path):
    res = prepare(recipe, code_dir, {}, tmp_path)
    assert res.returncode != 0 and "names no source tree" in res.stderr
    assert not (recipe / "src/manifest.json").exists()


def test_prepare_fails_on_an_unknown_commit(recipe, code_dir, tmp_path):
    pin = pins(code_dir)
    pin[TREES[-1]] = "0123456789abcdef0123456789abcdef01234567"
    res = prepare(recipe, code_dir, pin, tmp_path)
    assert res.returncode != 0
    assert TREES[-1] in res.stderr and not (recipe / "src/manifest.json").exists()


def test_prepare_fails_on_an_unpushed_commit(recipe, code_dir, tmp_path):
    clone = code_dir / TREES[0]
    (clone / "local.py").write_text("unpushed\n")
    git(clone, "add", "-A")
    git(clone, "commit", "-qm", "unpushed")
    res = prepare(recipe, code_dir, pins(code_dir), tmp_path)
    assert res.returncode != 0
    assert "remote-tracking" in res.stderr and not (recipe / "src/manifest.json").exists()


def test_prepare_fails_on_a_short_sha(recipe, code_dir, tmp_path):
    pin = pins(code_dir)
    pin[TREES[0]] = pin[TREES[0]][:12]
    res = prepare(recipe, code_dir, pin, tmp_path)
    assert res.returncode != 0 and "full commit SHA" in res.stderr


@pytest.fixture
def staged(recipe, code_dir, tmp_path):
    """The recipe committed and staged: a clean recipe hash in src/manifest.json."""
    assert prepare(recipe, code_dir, pins(code_dir), tmp_path).returncode == 0
    return recipe


def test_publish_builds_a_release_candidate_with_the_identity_and_ctest(staged, tmp_path):
    res = run_script(staged, PUBLISH_SCRIPT, tmp_path)
    assert res.returncode == 0, res.stderr
    m = json.loads((staged / "src/manifest.json").read_text())
    builds = engine_calls(tmp_path, "build")
    assert len(builds) == 2
    assert all("LAMMPS_RUN_TESTS=1" in b for b in builds)
    assert f"-t {REGISTRY_IMAGE}:{VERSION}-rc " in builds[0]
    assert f"--build-arg VERSION={VERSION}" in builds[0]
    assert f"--build-arg RECIPE_HASH={m['recipe_hash']}" in builds[0]
    assert f"--build-arg BUILD_ID={m['build_id']}" in builds[0]
    assert f"-t {REGISTRY_IMAGE}:{VERSION}-rc-sources" in builds[1]
    assert any(f"push {REGISTRY_IMAGE}:{VERSION}-rc" == p for p in engine_calls(tmp_path, "push"))
    assert "dummy-token" not in res.stdout + res.stderr


def test_publish_dev_builds_without_ctest_and_allows_a_dirty_recipe(staged, code_dir, tmp_path):
    (staged / "Dockerfile").write_text("FROM scratch\n# changed\n")
    assert run_script(staged, PREPARE_SCRIPT, tmp_path, CODE_DIR=code_dir).returncode == 0
    res = run_script(staged, PUBLISH_SCRIPT, tmp_path, TAG="dev")
    assert res.returncode == 0, res.stderr
    builds = engine_calls(tmp_path, "build")
    assert len(builds) == 2 and all("LAMMPS_RUN_TESTS=0" in b for b in builds)
    assert "dummy-token" not in res.stdout + res.stderr


def test_publish_refuses_a_release_candidate_of_a_dirty_recipe(staged, code_dir, tmp_path):
    (staged / "Dockerfile").write_text("FROM scratch\n# changed\n")
    assert run_script(staged, PREPARE_SCRIPT, tmp_path, CODE_DIR=code_dir).returncode == 0
    res = run_script(staged, PUBLISH_SCRIPT, tmp_path)
    assert res.returncode != 0 and "uncommitted" in res.stderr
    assert engine_calls(tmp_path) == []


def test_publish_refuses_a_manifest_staged_from_another_recipe_state(staged, tmp_path):
    (staged / "Dockerfile").write_text("FROM scratch\n# changed\n")
    res = run_script(staged, PUBLISH_SCRIPT, tmp_path, TAG="dev")
    assert res.returncode != 0 and "staged from another recipe state" in res.stderr
    assert engine_calls(tmp_path) == []


@pytest.mark.parametrize("tag", ["latest", str(VERSION), "foo", f"{VERSION}-sources"])
def test_publish_refuses_a_tag_other_than_dev_or_rc(staged, tmp_path, tag):
    res = run_script(staged, PUBLISH_SCRIPT, tmp_path, TAG=tag)
    assert res.returncode != 0 and RELEASE_SCRIPT in res.stderr
    assert engine_calls(tmp_path) == []


BUILD_ID = "20261118T120000Z"


def release(recipe, tmp_path, records=(BUILD_ID,), label=BUILD_ID, manifest_rc=1,
            manifest_out="manifest unknown", **env):
    releases = repo_root(recipe) / RELEASES_REL / str(VERSION)
    if records is not None:
        releases.mkdir(parents=True, exist_ok=True)
        for i, build_id in enumerate(records):
            (releases / f"cluster-{i}.json").write_text(json.dumps({"build_id": build_id}))
    return run_script(recipe, RELEASE_SCRIPT, tmp_path, STUB_LABEL=label,
                      STUB_MANIFEST_RC=manifest_rc, STUB_MANIFEST_OUT=manifest_out, **env)


def test_release_tags_and_pushes_n_and_latest_with_their_sources_images(recipe, tmp_path):
    res = release(recipe, tmp_path)
    assert res.returncode == 0, res.stderr
    image = REGISTRY_IMAGE
    rc, n = f"{image}:{VERSION}-rc", VERSION
    assert engine_calls(tmp_path, "tag") == [
        f"tag {rc} {image}:{n}", f"tag {rc} {image}:latest",
        f"tag {rc}-sources {image}:{n}-sources", f"tag {rc}-sources {image}:latest-sources"]
    # each sources tag is pushed before its image tag
    assert engine_calls(tmp_path, "push") == [
        f"push {image}:{n}-sources", f"push {image}:{n}",
        f"push {image}:latest-sources", f"push {image}:latest"]
    assert "dummy-token" not in res.stdout + res.stderr


def test_release_refuses_without_the_candidates_sources_image(recipe, tmp_path):
    res = release(recipe, tmp_path, STUB_SOURCES_RC=1)
    assert res.returncode != 0 and f"{VERSION}-rc-sources cannot be pulled" in res.stderr
    assert engine_calls(tmp_path, "tag") == [] and engine_calls(tmp_path, "push") == []


def test_release_accepts_docker_wording_for_a_free_tag(recipe, tmp_path):
    assert release(recipe, tmp_path, manifest_out="no such manifest: x/y:3").returncode == 0


def test_release_refuses_without_records(recipe, tmp_path):
    res = release(recipe, tmp_path, records=None)
    assert res.returncode != 0 and "no records" in res.stderr
    assert engine_calls(tmp_path, "tag") == [] and engine_calls(tmp_path, "push") == []


def test_release_refuses_a_record_of_another_build(recipe, tmp_path):
    res = release(recipe, tmp_path, records=(BUILD_ID, "20250101T000000Z"))
    assert res.returncode != 0 and "20250101T000000Z" in res.stderr
    assert engine_calls(tmp_path, "tag") == [] and engine_calls(tmp_path, "push") == []


def test_release_refuses_when_n_exists(recipe, tmp_path):
    res = release(recipe, tmp_path, manifest_rc=0, manifest_out="{}")
    assert res.returncode != 0 and "exists already" in res.stderr
    assert engine_calls(tmp_path, "tag") == [] and engine_calls(tmp_path, "push") == []


@pytest.mark.parametrize("out", ["unauthorized: authentication required", "not found", "404", ""])
def test_release_aborts_on_a_registry_error_that_is_not_manifest_unknown(recipe, tmp_path, out):
    res = release(recipe, tmp_path, manifest_out=out)
    assert res.returncode != 0 and "cannot tell" in res.stderr
    assert engine_calls(tmp_path, "tag") == [] and engine_calls(tmp_path, "push") == []


# ---- the harness verify.py and the gate check_release.py ----

VERIFICATION = ROOT / "verification"
COMPONENTS_HEADER = "component\torigin\ttest\tparts\tclusters\n"
KNOWN_HEADER = "component\ttest id\tcluster\tpart\treason\treference\n"
# Fake components: alpha runs in both parts of both clusters, beta in the cpu part of c1.
ALPHA = ("alpha", "alpha", "cpu,gpu", "c1,c2")
BETA = ("beta", "beta", "cpu", "c1")
OK = '#!/bin/sh\necho "PASS one"\necho "PASS two"\n'
SOURCES = {"gpaw": "a" * 40, "abTEM": "b" * 40}
BUILD = "20261201T101500Z"


def junit(cases, rc=1):
    """A test script that writes a junit file of (classname, name, outcome) cases and exits rc."""
    body = "".join(
        f'<testcase classname="{c}" name="{n}">' + {
            "pass": "", "skip": "<skipped/>",
            "fail": '<failure message="boom">trace</failure>'}[o] + "</testcase>"
        for c, n, o in cases)
    return (f'#!/bin/sh\ncat > "$VERIFY_JUNIT" <<\'EOF\'\n<testsuites><testsuite>{body}'
            f'</testsuite></testsuites>\nEOF\nexit {rc}\n')


class Suite:
    """A temporary git repository holding the recipe, verify.py, check_release.py, fake
    components and a manifest; the commit tagged `base` is the gate's base (VERSION B)."""

    def __init__(self, recipe, tmp_path):
        self.recipe, self.repo, self.tmp = recipe, repo_root(recipe), tmp_path
        self.vdir = self.repo / "verification"
        self.idir = self.vdir / IMAGE
        (self.vdir / "tests").mkdir(parents=True)
        self.idir.mkdir()
        for name in ("verify.py", "check_release.py"):
            shutil.copy(VERIFICATION / name, self.vdir / name)
        (recipe / "sources.txt").write_text("".join(f"{n} {s}\n" for n, s in SOURCES.items()))
        (recipe / REQUIREMENTS).write_text("# curated\nalpha>=1  # a\nBeta[extra]==2\n")
        self.components(ALPHA, BETA)
        self.scripts(alpha=OK, beta=OK)
        self.commit("suite")
        git(self.repo, "tag", "base")

    def commit(self, msg="change"):
        commit_all(self.repo, msg)

    def components(self, *rows, known=()):
        (self.idir / "components.tsv").write_text(
            COMPONENTS_HEADER + "".join(f"{c}\tsource\t{t}\t{p}\t{cl}\n" for c, t, p, cl in rows))
        (self.idir / "known-failures.tsv").write_text(
            KNOWN_HEADER + "".join("\t".join(k) + "\n" for k in known))

    def scripts(self, **bodies):
        for name, body in bodies.items():
            path = self.vdir / "tests" / name
            path.write_text(body)
            path.chmod(0o755)

    def tests_hash(self):
        return subprocess.run([self.recipe / HASH_SCRIPT, self.vdir / "tests"], check=True,
                              capture_output=True, text=True).stdout.strip()

    # -- the gate --
    def gate(self, **env):
        return subprocess.run([sys.executable, self.vdir / "check_release.py", IMAGE, "--base",
                               "base"], cwd=self.repo, capture_output=True, text=True,
                              env={**os.environ, **{k: str(v) for k, v in env.items()}})

    def base_at(self, version):
        """Move the gate's base to a commit whose VERSION is `version`."""
        (self.recipe / "VERSION").write_text(f"{version}\n")
        self.commit(f"base {version}")
        git(self.repo, "tag", "-f", "base")

    def release(self, version=VERSION + 1, mutate=None):
        """Bump VERSION, then write a complete, passing record for every required pair."""
        (self.recipe / "VERSION").write_text(f"{version}\n")
        self.commit("bump")
        records = {}
        for cluster in ("c1", "c2"):
            for part in ("cpu", "gpu"):
                comps = ["alpha", "beta"] if (cluster, part) == ("c1", "cpu") else ["alpha"]
                records[f"{cluster}-{part}"] = {
                    "image": IMAGE, "version": version, "build_id": BUILD,
                    "recipe_hash": recipe_hash(self.recipe), "sources": dict(SOURCES),
                    "tests_hash": self.tests_hash(), "lammps_ctest": True, "complete": True,
                    "cluster": cluster, "part": part,
                    "components": {c: {"status": "pass", "passed": 2, "failed": 0, "skipped": 0,
                                       "known_failed": 0, "unexpected": [], "stale_known": [],
                                       "seconds": 1} for c in comps}}
        if mutate:
            mutate(records)
        out = self.idir / "releases" / str(version)
        out.mkdir(parents=True)
        for name, rec in records.items():
            (out / f"{name}.json").write_text(json.dumps(rec))
        self.commit("records")

    # -- the harness --
    def manifest(self, **over):
        m = {"image": IMAGE, "version": VERSION + 1, "recipe_hash": recipe_hash(self.recipe),
             "build_id": BUILD, "sources": dict(SOURCES), "lammps_ctest": True}
        path = self.tmp / "manifest.json"
        path.write_text(json.dumps({**m, **over}))
        return path

    def verify(self, cluster, part, *args, scrub="unused-string", **env):
        full = {"PATH": os.environ["PATH"], "VERIFY_CLUSTER": cluster, "VERIFY_JOB_ID": "7",
                "VERIFY_IMAGE_DIGEST": "sha256:cc", "VERIFY_SCRUB": scrub,
                "VERIFY_WORK": str(self.tmp / "work"), "VERIFY_MANIFEST": str(self.manifest())}
        full.update({k: str(v) for k, v in env.items()})
        return subprocess.run([sys.executable, self.vdir / "verify.py", IMAGE, "--part", part,
                               *args], env=full, capture_output=True, text=True)

    def record(self, cluster, part, version=VERSION + 1):
        return json.loads((self.idir / "releases" / str(version) / f"{cluster}-{part}.json")
                          .read_text())


@pytest.fixture
def suite(recipe, tmp_path):
    return Suite(recipe, tmp_path)


def gate_fails(res, needle):
    assert res.returncode != 0, res.stdout
    assert needle in res.stdout, res.stdout


# gate

def test_gate_passes_a_complete_release(suite):
    suite.release()
    res = suite.gate()
    assert res.returncode == 0, res.stdout + res.stderr


def test_gate_passes_an_unchanged_recipe_at_the_same_version(suite):
    (suite.recipe / "README.md").write_text("docs only\n")
    suite.commit()
    assert suite.gate().returncode == 0


def test_gate_fails_a_recipe_change_without_a_bump(suite):
    (suite.recipe / "Dockerfile").write_text("FROM scratch\nRUN true\n")
    suite.commit()
    gate_fails(suite.gate(), f"VERSION is still {VERSION}")


def test_gate_fails_a_bump_by_two(suite):
    suite.release(VERSION + 2)
    gate_fails(suite.gate(), "exactly 1")


def test_gate_fails_a_missing_cluster_record(suite):
    suite.release(mutate=lambda recs: recs.pop("c2-gpu"))
    gate_fails(suite.gate(), "c2-gpu.json is missing")


def test_gate_fails_a_record_with_another_recipe_hash(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"].update(recipe_hash="0" * 64))
    gate_fails(suite.gate(), "c1-cpu.json has another recipe hash")


def test_gate_fails_a_record_of_another_version(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"].update(version=VERSION))
    gate_fails(suite.gate(), "c1-cpu.json has version")


def test_gate_fails_records_with_two_build_ids(suite):
    suite.release(mutate=lambda recs: recs["c2-cpu"].update(build_id="20250101T000000Z"))
    gate_fails(suite.gate(), "more than one build id")


def test_gate_fails_sources_that_differ_from_sources_txt(suite):
    suite.release(mutate=lambda recs: recs["c1-gpu"]["sources"].update(gpaw="c" * 40))
    gate_fails(suite.gate(), "c1-gpu.json has sources that differ")


def test_gate_fails_an_image_built_without_the_lammps_ctest(suite):
    suite.release(mutate=lambda recs: recs["c1-gpu"].update(lammps_ctest=False))
    gate_fails(suite.gate(), "LAMMPS ctest")


def test_gate_fails_an_incomplete_record(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"].update(complete=False))
    gate_fails(suite.gate(), "c1-cpu.json is incomplete")


def test_gate_fails_a_failed_component(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"]["components"]["beta"].update(status="fail"))
    gate_fails(suite.gate(), "beta is fail")


def test_gate_fails_a_component_that_was_not_run(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"]["components"]["beta"].update(status="not-run"))
    gate_fails(suite.gate(), "beta is not-run")


def test_gate_fails_a_non_empty_unexpected(suite):
    suite.release(mutate=lambda recs: recs["c2-gpu"]["components"]["alpha"].update(
        unexpected=["t::x"]))
    gate_fails(suite.gate(), "unexpected: t::x")


def test_gate_passes_stale_known_with_a_message(suite):
    suite.release(mutate=lambda recs: recs["c2-gpu"]["components"]["alpha"].update(
        stale_known=["t::old"]))
    res = suite.gate()
    assert res.returncode == 0, res.stdout
    assert "t::old" in res.stdout and "shorten the list" in res.stdout


def test_gate_fails_a_requirement_without_a_row(suite):
    suite.components(ALPHA)
    suite.release()
    gate_fails(suite.gate(), "beta is in the requirements file and has no row")


def test_gate_accepts_a_covered_by_row_for_a_requirement(suite):
    suite.components(ALPHA, ("beta", "covered-by:alpha", "cpu", "c1"))
    suite.release()
    assert suite.gate().returncode == 0


def test_gate_fails_a_test_file_that_does_not_exist(suite):
    suite.components(ALPHA, BETA, ("gamma", "gamma", "cpu", "c1"))
    suite.release()
    gate_fails(suite.gate(), "tests/gamma does not exist")


def test_gate_bootstraps_at_version_zero_with_a_recipe_change(suite):
    suite.base_at(0)
    (suite.recipe / "Dockerfile").write_text("FROM scratch\nRUN true\n")
    suite.components(ALPHA)  # a requirement without a row is no failure before release 1
    suite.commit()
    res = suite.gate()
    assert res.returncode == 0, res.stdout


def test_gate_fails_a_recipe_with_uncommitted_changes(suite):
    (suite.recipe / "Dockerfile").write_text("changed\n")
    gate_fails(suite.gate(), "uncommitted")


def test_gate_fails_a_record_copied_to_another_cluster_and_part(suite):
    suite.release(mutate=lambda recs: recs.update({"c1-gpu": copy.deepcopy(recs["c1-cpu"])}))
    gate_fails(suite.gate(), "c1-gpu.json is a record of c1-cpu")


def test_gate_fails_a_record_of_another_image(suite):
    suite.release(mutate=lambda recs: recs["c2-cpu"].update(image="other"))
    gate_fails(suite.gate(), "c2-cpu.json is a record of the image other")


def test_gate_fails_complete_that_is_not_true(suite):
    suite.release(mutate=lambda recs: recs["c1-cpu"].update(complete="false"))
    gate_fails(suite.gate(), "c1-cpu.json is incomplete")


def test_gate_fails_a_version_that_is_not_an_integer(suite):
    suite.base_at(0)
    suite.release(1, mutate=lambda recs: recs["c1-cpu"].update(version=True))
    gate_fails(suite.gate(), "c1-cpu.json has version True")


def test_gate_fails_tests_changed_after_the_records(suite):
    suite.release()
    suite.scripts(alpha=OK + "# weakened\n")
    suite.commit("weaken")
    gate_fails(suite.gate(), "has another tests hash")


def test_gate_fails_dirty_tests_even_when_the_record_says_dirty(suite):
    suite.release(mutate=lambda recs: [r.update(tests_hash="dirty") for r in recs.values()])
    (suite.vdir / "tests" / "alpha").write_text(OK + "# uncommitted\n")
    gate_fails(suite.gate(), "verification/tests has uncommitted changes")


@pytest.mark.parametrize("row", [("beta", "beta", "cpu", ""), ("beta", "beta", "", "c1")])
def test_gate_fails_a_row_without_clusters_or_parts(suite, row):
    suite.components(ALPHA, row)
    suite.release()
    gate_fails(suite.gate(), "beta lists no clusters or no parts")


@pytest.mark.parametrize("target", ["ghost", "gamma"])
def test_gate_fails_covered_by_a_component_without_a_test_of_its_own(suite, target):
    suite.components(ALPHA, ("beta", f"covered-by:{target}", "cpu", "c1"),
                     ("gamma", "covered-by:alpha", "cpu", "c1"))
    suite.release()
    gate_fails(suite.gate(), f"covered-by:{target}, which has no row with a test of its own")


def test_gate_fails_where_the_image_has_several_recipe_directories(suite):
    other = suite.repo / "shared/containers/other-arch" / IMAGE
    other.mkdir(parents=True)
    (other / "VERSION").write_text("0\n")
    suite.commit("second platform")
    res = suite.gate()
    assert res.returncode != 0 and "exactly one recipe directory" in res.stderr


def test_gate_reads_the_base_without_touching_the_worktrees_of_the_checkout(suite, tmp_path):
    shim = tmp_path / "bin"
    shim.mkdir()
    (shim / "git").write_text(f'#!/bin/sh\necho "$*" >> "{tmp_path}/git.log"\n'
                              f'exec {shutil.which("git")} "$@"\n')
    (shim / "git").chmod(0o755)
    (suite.recipe / "README.md").write_text("docs only\n")
    suite.commit()
    res = suite.gate(PATH=f"{shim}:{os.environ['PATH']}")
    assert res.returncode == 0, res.stdout + res.stderr
    assert (tmp_path / "git.log").exists()  # the shim saw the gate's git calls
    assert "worktree" not in (tmp_path / "git.log").read_text()


# harness

def test_verify_writes_a_record_per_part_and_the_gate_requires_both(suite):
    suite.release()  # the manifest of the image carries the same identity
    shutil.rmtree(suite.idir / "releases")
    for cluster, part in (("c1", "cpu"), ("c1", "gpu"), ("c2", "cpu")):
        assert suite.verify(cluster, part).returncode == 0
    rec = suite.record("c1", "cpu")
    assert rec["part"] == "cpu" and rec["cluster"] == "c1" and rec["complete"] is True
    assert set(rec["components"]) == {"alpha", "beta"}
    assert set(suite.record("c1", "gpu")["components"]) == {"alpha"}
    assert rec["tests_hash"] == suite.tests_hash()  # the recipe-hash construction on tests/
    assert (rec["build_id"], rec["image_digest"], rec["job_id"]) == (BUILD, "sha256:cc", "7")
    gate_fails(suite.gate(), "c2-gpu.json is missing")
    assert suite.verify("c2", "gpu").returncode == 0
    res = suite.gate()
    assert res.returncode == 0, res.stdout


def test_verify_marks_an_only_run_incomplete(suite):
    assert suite.verify("c1", "cpu", "--only", "alpha").returncode == 0
    rec = suite.record("c1", "cpu")
    assert rec["complete"] is False
    assert rec["components"]["alpha"]["status"] == "pass"
    assert rec["components"]["beta"]["status"] == "not-run"
    assert suite.verify("c1", "cpu", "--only", "nothing").returncode != 0


def test_verify_refuses_to_run_without_the_launcher_variables(suite):
    res = suite.verify("c1", "cpu", scrub="")
    assert res.returncode != 0 and "VERIFY_SCRUB" in res.stderr


def test_verify_counts_a_failure_in_the_list_and_one_outside_it(suite):
    cases = [("m.t", "a", "pass"), ("m.t", "known", "fail"), ("m.t", "new", "fail"),
             ("m.t", "s", "skip")]
    suite.scripts(alpha=junit(cases))
    suite.components(ALPHA, known=[("alpha", "m.t::known", "*", "*", "why", "")])
    res = suite.verify("c1", "cpu")
    assert res.returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "fail" and entry["unexpected"] == ["m.t::new"]
    assert (entry["passed"], entry["failed"], entry["skipped"], entry["known_failed"]) == (1, 2, 1, 1)
    assert "m.t::new" in (suite.idir / "releases/4/c1-cpu/alpha.log").read_text()


def test_verify_passes_a_run_whose_only_failures_are_listed(suite):
    suite.scripts(alpha=junit([("m", "a", "pass"), ("m", "known", "fail")]))
    suite.components(ALPHA, known=[("alpha", "m::known", "c1", "cpu", "why", "")])
    assert suite.verify("c1", "cpu").returncode == 0
    assert suite.record("c1", "cpu")["components"]["alpha"]["status"] == "pass"


@pytest.mark.parametrize("cluster, part, component", [
    ("c2", "cpu", "alpha"), ("c1", "gpu", "alpha"), ("c1", "cpu", "beta")])
def test_verify_does_not_apply_a_listed_failure_of_another_cluster_part_or_component(
        suite, cluster, part, component):
    suite.scripts(alpha=junit([("m", "a", "pass"), ("m", "known", "fail")]))
    suite.components(ALPHA, BETA, known=[(component, "m::known", cluster, part, "why", "")])
    assert suite.verify("c1", "cpu").returncode != 0


def test_verify_reports_a_listed_test_that_passes_as_stale(suite):
    suite.scripts(alpha=junit([("m", "a", "pass"), ("m", "old", "pass")], rc=0))
    suite.components(ALPHA, known=[("alpha", "m::old", "*", "*", "why", "")])
    assert suite.verify("c1", "cpu").returncode == 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "pass" and entry["stale_known"] == ["m::old"]


def test_verify_reads_pass_and_fail_lines(suite):
    suite.scripts(alpha='#!/bin/sh\necho "PASS a"\necho "FAIL b"\nexit 1\n')
    assert suite.verify("c1", "cpu").returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert (entry["passed"], entry["failed"], entry["unexpected"]) == (1, 1, ["b"])


def test_verify_fails_a_test_that_exits_non_zero_without_junit(suite):
    suite.scripts(alpha="#!/bin/sh\necho crashed\nexit 3\n")
    assert suite.verify("c1", "cpu").returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "fail" and entry["unexpected"] == ["exit status 3"]
    assert "crashed" in (suite.idir / "releases/4/c1-cpu/alpha.log").read_text()


def test_verify_fails_a_run_in_which_every_test_is_skipped(suite):
    suite.scripts(alpha=junit([("m", "a", "skip"), ("m", "b", "skip")], rc=0))
    assert suite.verify("c1", "cpu").returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "fail" and entry["skipped"] == 2
    assert entry["unexpected"] == ["no test results"]


@pytest.mark.parametrize("executable", [False, None])
def test_verify_fails_a_test_file_that_cannot_run_and_still_writes_the_record(suite, executable):
    path = suite.vdir / "tests" / "alpha"
    if executable is None:
        path.unlink()
    else:
        path.chmod(0o644)
    assert suite.verify("c1", "cpu").returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "fail" and entry["unexpected"] == ["exit status 127"]
    assert suite.record("c1", "cpu")["components"]["beta"]["status"] == "pass"
    assert "cannot run" in (suite.idir / "releases/4/c1-cpu/alpha.log").read_text()


def test_verify_scrubs_the_values_of_the_record_not_its_keys(suite):
    assert suite.verify("c1", "cpu", scrub="status:pass:version").returncode == 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "<scrubbed>" and "passed" in entry
    assert suite.record("c1", "cpu")["version"] == VERSION + 1


def test_verify_fails_where_the_image_has_several_recipe_directories(suite):
    (suite.repo / "shared/containers/other-arch" / IMAGE).mkdir(parents=True)
    res = suite.verify("c1", "cpu")
    assert res.returncode != 0 and "exactly one recipe directory" in res.stderr
    assert not (suite.idir / "releases").exists()


def test_verify_fails_a_test_that_reports_nothing(suite):
    suite.scripts(alpha="#!/bin/sh\nexit 0\n")
    assert suite.verify("c1", "cpu").returncode != 0
    assert suite.record("c1", "cpu")["components"]["alpha"]["unexpected"] == ["no test results"]


def test_verify_reports_a_preflight_failure_as_fail_never_as_skipped(suite):
    suite.scripts(alpha='#!/bin/sh\necho "FAIL preflight: library missing"\nexit 1\n')
    assert suite.verify("c1", "cpu").returncode != 0
    entry = suite.record("c1", "cpu")["components"]["alpha"]
    assert entry["status"] == "fail" and entry["skipped"] == 0
    assert entry["unexpected"] == ["preflight: library missing"]


def test_verify_removes_every_scrub_string_from_the_record_and_the_logs(suite):
    secrets = ["secretuser", "/secret/path", "acct-123"]
    suite.scripts(alpha=(
        '#!/bin/sh\necho "PASS /secret/path/x"\necho "FAIL acct-123 of secretuser"\n'
        'echo "secretuser at /secret/path/y" >&2\nexit 1\n'),
        beta=junit([("secretuser.m", "t", "fail")]))
    res = suite.verify("c1", "cpu", scrub=":".join(secrets))
    assert res.returncode != 0
    files = [p for p in (suite.idir / "releases").rglob("*") if p.is_file()]
    assert len(files) == 4  # record, two logs, README
    for p in files:
        assert not any(s in p.read_text() for s in secrets), p
    assert "<scrubbed>" in (suite.idir / "releases/4/c1-cpu/alpha.log").read_text()
    assert res.returncode != 0 and not any(s in res.stdout + res.stderr for s in secrets)


def test_verify_generates_a_table_of_components_by_cluster_and_part(suite):
    suite.release()
    shutil.rmtree(suite.idir / "releases")
    for cluster, part in (("c1", "cpu"), ("c1", "gpu"), ("c2", "cpu"), ("c2", "gpu")):
        assert suite.verify(cluster, part).returncode == 0
    lines = (suite.idir / "releases/4/README.md").read_text().splitlines()
    table = [line for line in lines if line.startswith("|")]
    assert table[0].split(" | ")[1:] == ["c1-cpu", "c1-gpu", "c2-cpu", "c2-gpu |"]
    assert len(table) == 2 + 2  # header, separator, one row per component
    cell = "pass 2 / 0 / 0 / 0"
    assert table[2] == f"| alpha | {cell} | {cell} | {cell} | {cell} |"
    assert table[3] == f"| beta | {cell} | - | - | - |"


# the abTEM component test

@pytest.fixture
def abtem_suite(suite, tmp_path):
    """The real tests/abtem, with fake `abtem` and `cupy` modules on PYTHONPATH."""
    shutil.copy(VERIFICATION / "tests" / ABTEM, suite.vdir / "tests" / ABTEM)
    (suite.vdir / "tests" / ABTEM).chmod(0o755)
    suite.components((ABTEM, ABTEM, "cpu,gpu", "c1"))
    fake = tmp_path / "fake"
    (fake / "abtem").mkdir(parents=True)
    (fake / "abtem/__init__.py").write_text("")
    (fake / "cupy").mkdir()
    (fake / "cupy/__init__.py").write_text(
        "import os\n\nclass cuda:\n    class runtime:\n"
        "        getDeviceCount = staticmethod(lambda: int(os.environ['FAKE_GPUS']))\n")
    suite.fake = fake
    return suite


@pytest.mark.parametrize("part, gpus, message", [
    ("cpu", 1, "a GPU is visible in the cpu part"),
    ("gpu", 0, "no GPU is visible in the gpu part"),
    ("cpu", 0, "not from /opt/src/abTEM")])
def test_abtem_preflight_fails_instead_of_skipping(abtem_suite, part, gpus, message):
    res = abtem_suite.verify("c1", part, PYTHONPATH=abtem_suite.fake, FAKE_GPUS=gpus)
    assert res.returncode != 0
    entry = abtem_suite.record("c1", part)["components"][ABTEM]
    assert entry["status"] == "fail" and entry["skipped"] == 0
    assert any(message in t for t in entry["unexpected"]), entry


def test_abtem_runs_the_suite_with_the_marker_of_the_part_and_a_junit_file():
    path = VERIFICATION / "tests" / ABTEM
    spec = importlib.util.spec_from_loader("abtem_test", SourceFileLoader("abtem_test", str(path)))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cpu = module.pytest_command("cpu", "j.xml")
    gpu = module.pytest_command("gpu", "j.xml")
    for command, marker in ((cpu, "not gpu"), (gpu, "gpu")):
        assert command[command.index("-m") + 1] == marker
        assert "--runslow" in command and "--junitxml=j.xml" in command
        assert command[command.index("--project") + 1] == "/opt/src/abTEM"
    assert Path(cpu[1]).samefile(ROOT / "shared/testing/run_pytest.py")


# the launchers

@pytest.mark.parametrize("name", LAUNCHERS)
def test_launcher_is_valid_bash_and_names_no_account(name):
    path = VERIFICATION / "clusters" / name
    subprocess.run(["bash", "-n", path], check=True)
    text = path.read_text()
    account = [line for line in text.splitlines() if line.startswith("#SBATCH --account=")]
    assert len(account) == 1 and account[0].startswith("#SBATCH --account=<project>")
    for variable in ("VERIFY_CLUSTER", "VERIFY_IMAGE_DIGEST", "VERIFY_JOB_ID", "VERIFY_SCRUB",
                     "VERIFY_WORK"):
        assert variable in text
    code = "\n".join(line for line in text.splitlines()
                     if not line.startswith("#") or line.startswith("#SBATCH"))
    gpu_flags = re.findall(r"--gpu\b|--nv\b|--gpus-per-node", code)
    assert bool(gpu_flags) == name.endswith("-gpu.sbatch"), (name, gpu_flags)


def run_launcher(name, tmp_path, *args, launcher=None, **env):
    """Run a launcher with stub srun, podman-hpc and apptainer that log their arguments (and
    the VERIFY_ variables) to tmp_path/engine.log; return the process and the log lines."""
    stubs = tmp_path / "stubs"
    stubs.mkdir(exist_ok=True)
    for tool, body in {
            "srun": 'while [ "${1#--}" != "$1" ]; do shift; done; exec "$@"',
            # As on Perlmutter: an image in the shared read-only store is listed by `images`
            # but unknown to `image inspect`.
            "podman-hpc": 'case "$1" in images) printf "%s" "${STUB_PM_DIGEST-sha256:abc}"; '
                          '[ -z "${STUB_PM_DIGEST-x}" ] || echo; exit 0 ;; image) echo "Error: $3: '
                          'image not known" >&2; exit 125 ;; esac\necho "$*" >> "$STUB_LOG"; '
                          'echo "$VERIFY_IMAGE_DIGEST $VERIFY_SCRUB" >> "$STUB_LOG"',
            "apptainer": 'echo "$*" >> "$STUB_LOG"; '
                         'echo "$VERIFY_SCRUB:$NUMBA_CACHE_DIR" >> "$STUB_LOG"'}.items():
        (stubs / tool).write_text(f"#!/bin/sh\n{body}\n")
        (stubs / tool).chmod(0o755)
    for dirname in ("home", "scratch/u1", "proj/software/containers"):
        (tmp_path / dirname).mkdir(parents=True, exist_ok=True)
    (tmp_path / "proj/software/containers" / f"{IMAGE}.sif").write_text("sif")
    full = {"PATH": f"{stubs}:{os.environ['PATH']}", "USER": "u1", "HOME": str(tmp_path / "home"),
            "SLURM_JOB_ID": "5", "STUB_LOG": str(tmp_path / "engine.log"),
            "PROJECTS_BASE": str(tmp_path / "proj")}
    full.update({k: str(v) for k, v in env.items()})
    res = subprocess.run(["bash", launcher or VERIFICATION / "clusters" / name, *args], env=full,
                         capture_output=True, text=True)
    log = tmp_path / "engine.log"
    return res, (log.read_text().splitlines() if log.exists() else [])


def perlmutter(name, tmp_path, *args, **env):
    return run_launcher(name, tmp_path, *args, SCRATCH=tmp_path / "scratch/u1", **env)


@pytest.mark.parametrize("part", ["cpu", "gpu"])
def test_perlmutter_launcher_stops_when_podman_hpc_lists_no_such_image(tmp_path, part):
    res, log = perlmutter(f"perlmutter-{part}.sbatch", tmp_path, IMAGE, STUB_PM_DIGEST="")
    assert res.returncode != 0 and not log  # the container never starts
    assert f"IMAGE=ghcr.io/idrobolab/{IMAGE}:" in res.stdout
    assert "not in podman-hpc images" in res.stderr


@pytest.mark.parametrize("part", ["cpu", "gpu"])
def test_perlmutter_launcher_runs_the_release_candidate_with_the_verify_variables(tmp_path, part):
    res, log = perlmutter(f"perlmutter-{part}.sbatch", tmp_path, IMAGE, "--only", ABTEM)
    assert res.returncode == 0, res.stderr
    call = log[0]
    assert f"ghcr.io/idrobolab/{IMAGE}:0-rc python verification/verify.py {IMAGE} --part {part} " \
           f"--only {ABTEM}" in call
    assert ("--gpu " in call) == (part == "gpu")
    assert "_NUM_THREADS" not in call  # the image's OMP/OPENBLAS = 1: GPAW warns above 1
    digest, scrub = log[1].split(" ", 1)
    assert digest == "sha256:abc" and "u1" in scrub.split(":")
    assert not list((tmp_path / "scratch/u1").glob("verify-*"))  # the work directory is removed


@pytest.mark.parametrize("env, image", [
    ({"IMAGE": IMAGE, "TAG": "7-rc"}, f"ghcr.io/idrobolab/{IMAGE}:7-rc"),
    ({"IMAGE": "other", "IMAGE_OWNER": "o"}, "ghcr.io/o/other:0-rc"),
    ({"IMAGE": "reg.example.com/x/y:z"}, "reg.example.com/x/y:z")])
def test_perlmutter_launcher_qualifies_a_bare_image_name_and_keeps_a_reference(
        tmp_path, env, image):
    res, log = perlmutter("perlmutter-cpu.sbatch", tmp_path, IMAGE, **env)
    assert res.returncode == 0, res.stderr
    assert f" {image} python " in log[0]


@pytest.mark.parametrize("name", ["perlmutter-cpu.sbatch", "perlmutter-gpu.sbatch"])
def test_perlmutter_launcher_fails_where_the_image_has_several_recipe_directories(tmp_path, name):
    repo = tmp_path / "repo"
    (repo / "verification/clusters").mkdir(parents=True)
    shutil.copy(VERIFICATION / "clusters" / name, repo / "verification/clusters" / name)
    (repo / "verification/verify.py").write_text("")
    for platform in ("a", "b"):
        (repo / "shared/containers" / platform / IMAGE).mkdir(parents=True)
        (repo / "shared/containers" / platform / IMAGE / "VERSION").write_text("0\n")
    res, log = perlmutter(name, tmp_path, IMAGE, launcher=repo / "verification/clusters" / name)
    assert res.returncode != 0 and "exactly one recipe directory" in res.stderr and not log


@pytest.mark.parametrize("part", ["cpu", "gpu"])
def test_delta_launcher_uses_the_personal_scratch_area_and_no_scratch_variable(tmp_path, part):
    res, log = run_launcher(f"delta-{part}.sbatch", tmp_path, IMAGE,
                            SCRATCH_BASE=tmp_path / "scratch")
    assert res.returncode == 0, res.stderr
    assert ("--nv " in log[0]) == (part == "gpu")
    assert "--writable-tmpfs " in log[0]  # run_pytest.py installs test dependencies into /opt/venv
    assert f"{tmp_path}/scratch/u1/verify-5/numba" in log[1].split(":")  # NUMBA_CACHE_DIR
    assert f"python verification/verify.py {IMAGE} --part {part}" in log[0]
    assert f"{tmp_path}/scratch/u1" in log[1].split(":")
    assert not list((tmp_path / "scratch/u1").glob("verify-*"))  # removed at the end
    text = (VERIFICATION / "clusters" / f"delta-{part}.sbatch").read_text()
    code = re.sub(r"(?m)^(?!#SBATCH).*?#.*$", lambda m: m.group().split("#")[0], text)
    assert not re.search(r"\$\{?SCRATCH(?![_A-Za-z])", code)


AVX512_CHECK = ROOT / RECIPE_REL / "check-no-avx512.sh"


def avx512_check(tmp_path, insn, name="x.o", sdk=(), archive=False):
    """Run check-no-avx512.sh on a directory holding one object (or a static archive of it)
    assembled from one instruction, with `sdk` listed in NVIDIA-REDIST-FILES.txt."""
    dist = tmp_path / "dist"
    (dist / "lib").mkdir(parents=True)
    (tmp_path / "x.s").write_text(f".text\n{insn}\n")
    obj = tmp_path / "x.o"
    subprocess.run(["as", tmp_path / "x.s", "-o", obj], check=True)
    if archive:
        subprocess.run(["ar", "rcs", dist / "lib" / name, obj], check=True)
    else:
        shutil.copy(obj, dist / "lib" / name)
    (dist / "lib" / "README").write_text("not an object\n")
    (dist / "NVIDIA-REDIST-FILES.txt").write_text("".join(f"{n}  some/path\n" for n in sdk))
    return subprocess.run(["bash", AVX512_CHECK, dist], capture_output=True, text=True)


@pytest.mark.parametrize("insn", [
    "vpxord %zmm0, %zmm0, %zmm0",
    "vpaddd %ymm17, %ymm17, %ymm17",  # EVEX-only register, no zmm
    "kmovw %k1, %eax",
])
@pytest.mark.parametrize("archive", [False, True])
def test_avx512_check_fails_on_an_avx512_instruction(tmp_path, insn, archive):
    res = avx512_check(tmp_path, insn, name="x.a" if archive else "x.o", archive=archive)
    assert res.returncode == 1
    assert "AVX-512: lib/x." in res.stdout and "1 file(s)" in res.stderr


def test_avx512_check_passes_avx2_code(tmp_path):
    res = avx512_check(tmp_path, "vpaddd %ymm15, %ymm1, %ymm1")
    assert res.returncode == 0, res.stdout + res.stderr
    assert "1 files checked" in res.stdout


def test_avx512_check_reports_but_does_not_check_an_sdk_file(tmp_path):
    res = avx512_check(tmp_path, "vpxord %zmm0, %zmm0, %zmm0", name="libnvf.so", sdk=["libnvf.so"])
    assert res.returncode == 1  # the SDK file was the only object: nothing checked
    assert "SDK file, not checked: lib/libnvf.so: 1 AVX-512 instructions" in res.stdout
    assert "no ELF file or archive" in res.stderr
