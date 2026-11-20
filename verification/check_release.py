#!/usr/bin/env python3
"""The release gate: does the head of this checkout carry what its version claims?

    python verification/check_release.py <image> --base <ref>

Let B and H be the image's VERSION at <ref> and in the working tree.
- H = B: the recipe hash equals the one at <ref>, or H = 0 (no release yet).
- H = B + 1: releases/H/ holds a complete record for every (cluster, part) that
  components.tsv requires; all records of the release share one build id; each has version H,
  the head's recipe hash, the sources of sources.txt and `lammps_ctest` true; every component
  required in that part on that cluster passed with no unexpected failure. A `stale_known`
  entry is printed as a request to shorten known-failures.tsv and does not fail.
- Any other H fails.
- Always: every row of components.tsv lists clusters and parts and has a `test` file that
  exists, or `covered-by:<component>` of a row that has one, whose test file names the row's
  component in its module-level `PREFLIGHT_LIBRARIES` (a tuple of string literals, read with
  `ast` without importing the test; the preflight iterates over the same tuple). From H = 1 on,
  every package of the recipe's requirements file has a row in components.tsv.
- Beyond the spec: each record's `tests_hash` equals the recipe-hash construction applied to
  verification/tests/ at the head, so tests changed after the cluster runs fail the gate; a
  record names its own image, cluster and part, as its file name does.

The personal-data check over verification/ is the repository's personal-data workflow, which
scans the whole tree. The records are trusted as committed: no CI runner has the cluster GPUs.
Exit status 0 when the gate passes. Python standard library only.
"""
import argparse
import ast
import json
import re
import subprocess
import sys
import tempfile

from verify import HERE, ROOT, items, own_components, read_tsv, recipe_dir, recipe_hash


def normalized(name):
    return name.lower().replace("_", "-")


def preflight_libraries(test):
    """The names in the module-level PREFLIGHT_LIBRARIES of the test file, as the gate reads
    them: without importing it. Empty when the file is missing, is no Python, or declares no
    literal tuple."""
    try:
        tree = ast.parse(test.read_text())
        for node in tree.body:
            if isinstance(node, ast.Assign) and any(
                    isinstance(t, ast.Name) and t.id == "PREFLIGHT_LIBRARIES"
                    for t in node.targets):
                return {normalized(name) for name in ast.literal_eval(node.value)}
    except (OSError, SyntaxError, ValueError):
        pass
    return set()


def requirement_names(path):
    names = set()
    for line in path.read_text().splitlines():
        m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", line.split("#")[0].strip())
        if m:
            names.add(normalized(m.group()))
    return names


def base_recipe_hash(image, base, rel):
    """The recipe hash of the recipe directory `rel` at the git ref `base`, from a throwaway
    clone: the checkout under test is only read."""
    with tempfile.TemporaryDirectory() as tmp:
        commit = subprocess.run(["git", "-C", ROOT, "rev-parse", f"{base}^{{commit}}"],
                                check=True, capture_output=True, text=True).stdout.strip()
        subprocess.run(["git", "clone", "-q", "--shared", ROOT, tmp], check=True)
        subprocess.run(["git", "-C", tmp, "-c", "advice.detachedHead=false", "checkout", "-q",
                        commit], check=True)
        return recipe_hash(image, f"{tmp}/{rel}")


def check_release(image, base):
    """Return the failures and the notes of the gate."""
    errors, notes = [], []
    recipe = recipe_dir(image)
    version = int(recipe.joinpath("VERSION").read_text())
    rel = recipe.relative_to(ROOT)
    base_version = int(subprocess.run(
        ["git", "-C", ROOT, "show", f"{base}:{rel}/VERSION"], check=True, capture_output=True,
        text=True).stdout)
    head_hash = recipe_hash(image, recipe)
    rows = own_components(image)
    tests_of = {r["component"]: r["test"] for r in rows}

    for row in read_tsv(HERE / image / "components.tsv"):
        comp, test = row["component"], row["test"]
        if test.startswith("covered-by:"):
            covering = tests_of.get(test[len("covered-by:"):])
            if covering is None:
                errors.append(f"{comp} is {test}, which has no row with a test of its own")
            elif normalized(comp) not in preflight_libraries(HERE / "tests" / covering):
                errors.append(f"{comp} is {test}, but tests/{covering} does not name {comp} "
                              "in PREFLIGHT_LIBRARIES")
            continue
        if not items(row["clusters"]) or not items(row["parts"]):
            errors.append(f"{comp} lists no clusters or no parts")
        if not (HERE / "tests" / test).is_file():
            errors.append(f"{comp}: test file tests/{test} does not exist")
    if version > 0:
        listed = {normalized(r["component"]) for r in read_tsv(HERE / image / "components.tsv")}
        for name in sorted(requirement_names(recipe / f"requirements-{image}.txt") - listed):
            errors.append(f"{name} is in the requirements file and has no row in components.tsv")

    if head_hash == "dirty":
        errors.append("the recipe has uncommitted changes")
    elif version == base_version:
        if version != 0 and head_hash != base_recipe_hash(image, base, rel):
            errors.append(f"the recipe changed since {base} and VERSION is still {version}")
    elif version == base_version + 1:
        check_records(image, version, head_hash, recipe, rows, errors, notes)
    else:
        errors.append(f"VERSION is {version}, at {base} it is {base_version}: "
                      "a release raises it by exactly 1")
    return errors, notes


def check_records(image, version, head_hash, recipe, rows, errors, notes):
    tests_hash = recipe_hash(image, HERE / "tests")
    if tests_hash == "dirty":
        errors.append("verification/tests has uncommitted changes")
    release_dir = HERE / image / "releases" / str(version)
    sources = dict(line.split() for line in (recipe / "sources.txt").read_text().splitlines()
                   if line.strip())
    records = {p.stem: json.loads(p.read_text()) for p in sorted(release_dir.glob("*.json"))}
    required = {}
    for row in rows:
        for cluster in items(row["clusters"]):
            for part in items(row["parts"]):
                required.setdefault(f"{cluster}-{part}", []).append(row["component"])

    for name in sorted(set(required) - set(records)):
        errors.append(f"releases/{version}/{name}.json is missing")
    if len({r["build_id"] for r in records.values()}) > 1:
        errors.append(f"releases/{version} holds records of more than one build id")
    for name, rec in records.items():
        where = f"releases/{version}/{name}.json"
        for ok, what in ((rec["image"] == image, f"is a record of the image {rec['image']}"),
                         (f"{rec['cluster']}-{rec['part']}" == name,
                          f"is a record of {rec['cluster']}-{rec['part']}"),
                         (rec["complete"] is True, "is incomplete"),
                         (type(rec["version"]) is int and rec["version"] == version,
                          f"has version {rec['version']}"),
                         (rec["tests_hash"] == tests_hash, "has another tests hash"),
                         (rec["recipe_hash"] == head_hash, "has another recipe hash"),
                         (rec["sources"] == sources, "has sources that differ from sources.txt"),
                         (rec["lammps_ctest"] is True, "is of an image built without the "
                          "LAMMPS ctest")):
            if not ok:
                errors.append(f"{where} {what}")
        for comp in required.get(name, []):
            entry = rec["components"].get(comp, {"status": "missing", "unexpected": []})
            if entry["status"] != "pass" or entry["unexpected"]:
                errors.append(f"{where}: {comp} is {entry['status']}"
                              + (f", unexpected: {', '.join(entry['unexpected'])}"
                                 if entry["unexpected"] else ""))
            for tid in entry.get("stale_known", []):
                notes.append(f"{where}: {comp}: {tid} is listed in known-failures.tsv and "
                             "passed: shorten the list")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("image")
    ap.add_argument("--base", required=True, help="the git ref the pull request merges into")
    args = ap.parse_args(argv)
    errors, notes = check_release(args.image, args.base)
    for note in notes:
        print("note:", note)
    for error in errors:
        print("FAIL:", error)
    if not errors:
        print("release gate passed")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
