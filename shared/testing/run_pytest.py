"""Run a package's pytest suite inside the idrobolab container.

    python ~/idrobolab-env/shared/testing/run_pytest.py [--project DIR] [pytest arguments ...]

The image carries no pytest, and none of the test dependencies of the packages it installs
editable (abTEM, GPAW, gpaw-weaver). This script installs the test dependencies the project
declares into the container's own /opt/venv, which `podman-hpc run --rm` discards
afterwards, and then runs pytest with the remaining arguments.

The project is the directory holding its pyproject.toml: `--project DIR`, or else the
working directory. Its test dependencies are the `test` dependency group
(`[dependency-groups]`), or else the `test` optional dependencies. They are installed as
plain packages, never by `pip install -e <project>[test]`: a checkout mounted read-only
cannot take the egg-info that would write. A project that declares neither (GPAW and
gpaw-weaver, as of writing) gets pytest alone. The project itself is not reinstalled. Put
the checkout under test first on PYTHONPATH, or bind it over /opt/src/<name>; the script
prints which copy Python imports, with the same import path as the pytest process.

pytest runs with `-p no:cacheprovider`. The cache plugin writes .pytest_cache into the
rootdir at the end of the session; on a read-only checkout that fails, which is an error
after every test has run in a project that turns warnings into errors (abTEM does).

Run it with the container's `python`, not `uv run`: it installs into the interpreter that
runs it, which has to be the one the tests run in.
"""
import subprocess
import sys
import tomllib
from pathlib import Path


def group_requirements(groups, name):
    requirements = []
    for entry in groups.get(name, []):
        if isinstance(entry, dict):
            requirements += group_requirements(groups, entry["include-group"])
        else:
            requirements.append(entry)
    return requirements


def main(argv):
    project = Path.cwd()
    if argv[:1] == ["--project"]:
        project, argv = Path(argv[1]).resolve(), argv[2:]
    pyproject = tomllib.loads((project / "pyproject.toml").read_text())

    requirements = group_requirements(pyproject.get("dependency-groups", {}), "test")
    if not requirements:
        optional = pyproject.get("project", {}).get("optional-dependencies", {})
        requirements = list(optional.get("test", []))
    # A test group need not list pytest itself (abTEM's pulls it in through pytest-cov);
    # pip merges this with any constraint the group puts on it.
    requirements.append("pytest")

    print("installing:", " ".join(requirements), flush=True)
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "--no-cache-dir",
                           "--disable-pip-version-check", *requirements])

    # In a child process like pytest's, so the current directory is on the path as it is there.
    name = pyproject.get("project", {}).get("name", "").lower().replace("-", "_")
    if name:
        check = f"import {name}; print('{name} imported from', {name}.__file__)"
        subprocess.call([sys.executable, "-c", check])

    return subprocess.call([sys.executable, "-m", "pytest", "-p", "no:cacheprovider", *argv])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
