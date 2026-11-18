"""Tests of the version identity of the idrobolab recipe: recipe-hash.sh and
prepare_build_context.sh, run in a temporary copy of the recipe's scripts with temporary
source repositories (a bare origin and a clone each), so nothing depends on /workspaces/code.
Run: pytest verification/test_harness.py"""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
RECIPE_REL = Path("shared/containers/x86_64-cuda/idrobolab")
SCRIPTS = ("recipe-hash.sh", "prepare_build_context.sh")


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
    (d / "VERSION").write_text("3\n")
    (d / "README.md").write_text("docs\n")
    (d / "Dockerfile").write_text("FROM scratch\n")
    (repo / ".gitignore").write_text("src/\nlammps-gpu-selftest.sh\n")
    core = repo / "core/lammps"
    core.mkdir(parents=True)
    (core / "lammps-gpu-selftest.sh").write_text("#!/bin/sh\n")
    git(repo, "init", "-q")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "recipe")
    return d


def recipe_hash(d):
    return subprocess.run([d / "recipe-hash.sh"], check=True, capture_output=True,
                          text=True).stdout.strip()


def commit_all(d, msg):
    git(d, "add", "-A", ".")
    git(d, "commit", "-qm", msg)


def test_recipe_hash_is_equal_for_equal_trees(recipe, tmp_path):
    other = tmp_path / "copy"
    shutil.copytree(recipe.parent.parent.parent.parent, other)
    h = recipe_hash(recipe)
    assert re.fullmatch(r"[0-9a-f]{64}", h)
    assert recipe_hash(other / RECIPE_REL) == h


def test_recipe_hash_ignores_readme_only(recipe):
    h = recipe_hash(recipe)
    (recipe / "README.md").write_text("other docs\n")
    commit_all(recipe, "readme")
    assert recipe_hash(recipe) == h
    (recipe / "Dockerfile").write_text("FROM scratch\nRUN true\n")
    commit_all(recipe, "dockerfile")
    assert recipe_hash(recipe) not in (h, "dirty")


@pytest.mark.parametrize("change", ["edit", "new file", "staged"])
def test_recipe_hash_is_dirty_with_an_uncommitted_change(recipe, change):
    if change == "edit":
        (recipe / "Dockerfile").write_text("changed\n")
    else:
        (recipe / "new.txt").write_text("x\n")
        if change == "staged":
            git(recipe, "add", "new.txt")
    assert recipe_hash(recipe) == "dirty"


def test_recipe_hash_ignores_staged_build_inputs(recipe):
    (recipe / "src").mkdir()
    (recipe / "src/x").write_text("x\n")
    (recipe / "lammps-gpu-selftest.sh").write_text("#!/bin/sh\n")
    assert recipe_hash(recipe) != "dirty"


@pytest.fixture
def code_dir(tmp_path):
    """gpaw, gpaw-weaver, abTEM: each a clone of a bare origin, with two pushed commits."""
    code = tmp_path / "code"
    for name in ("gpaw", "gpaw-weaver", "abTEM"):
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
    return {n: git(code / n, "rev-parse", rev) for n in ("gpaw", "gpaw-weaver", "abTEM")}


def prepare(recipe, code, pin):
    (recipe / "sources.txt").write_text("".join(f"{n} {s}\n" for n, s in pin.items()))
    commit_all(recipe, "sources")
    return subprocess.run([recipe / "prepare_build_context.sh"], env={"CODE_DIR": str(code),
                          "PATH": os.environ["PATH"]}, capture_output=True, text=True)


def test_prepare_stages_the_pinned_commits_and_writes_the_manifest(recipe, code_dir, tmp_path):
    pin = pins(code_dir, "HEAD~1")  # not the head: the pin decides
    res = prepare(recipe, code_dir, pin)
    assert res.returncode == 0, res.stderr
    for name, sha in pin.items():
        want = tmp_path / f"archive-{name}"
        want.mkdir()
        archive = subprocess.run(["git", "-C", code_dir / name, "archive", sha], check=True,
                                 capture_output=True).stdout
        subprocess.run(["tar", "-xf", "-", "-C", want], input=archive, check=True)
        subprocess.run(["diff", "-r", want, recipe / "src" / name], check=True)
    m = json.loads((recipe / "src/manifest.json").read_text())
    assert m["image"] == "idrobolab"
    assert m["version"] == 3
    assert m["recipe_hash"] == recipe_hash(recipe)
    assert re.fullmatch(r"\d{8}T\d{6}Z", m["build_id"])
    assert m["sources"] == pin


def test_prepare_fails_on_an_unknown_commit(recipe, code_dir):
    pin = pins(code_dir)
    pin["abTEM"] = "0123456789abcdef0123456789abcdef01234567"
    res = prepare(recipe, code_dir, pin)
    assert res.returncode != 0
    assert "abTEM" in res.stderr and not (recipe / "src/manifest.json").exists()


def test_prepare_fails_on_an_unpushed_commit(recipe, code_dir):
    clone = code_dir / "gpaw"
    (clone / "local.py").write_text("unpushed\n")
    git(clone, "add", "-A")
    git(clone, "commit", "-qm", "unpushed")
    res = prepare(recipe, code_dir, pins(code_dir))
    assert res.returncode != 0
    assert "remote-tracking" in res.stderr and not (recipe / "src/manifest.json").exists()


def test_prepare_fails_on_a_short_sha(recipe, code_dir):
    pin = pins(code_dir)
    pin["gpaw"] = pin["gpaw"][:12]
    res = prepare(recipe, code_dir, pin)
    assert res.returncode != 0 and "full commit SHA" in res.stderr
