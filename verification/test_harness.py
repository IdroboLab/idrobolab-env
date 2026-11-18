"""Tests of the version identity of the idrobolab recipe: recipe-hash.sh,
prepare_build_context.sh, publish.sh and release.sh, run in a temporary copy of the recipe's
scripts with temporary source repositories (a bare origin and a clone each) and a stub
container engine that only logs its calls, so nothing touches the network, a registry or a
credential, and nothing depends on a local checkout of the sources.
Run: pytest verification/test_harness.py"""
import json
import os
import re
import shutil
import subprocess
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

STUB_ENGINE = """#!/bin/bash
echo "$*" >> "$STUB_LOG"
case "$1 $2" in
    "manifest inspect") [[ "$3" == *-rc-sources ]] && exit "${STUB_SOURCES_RC:-0}"
        printf '%s\\n' "${STUB_MANIFEST_OUT:-}"; exit "${STUB_MANIFEST_RC:-1}" ;;
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
    assert res.returncode != 0 and f"{VERSION}-rc-sources does not exist" in res.stderr
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
