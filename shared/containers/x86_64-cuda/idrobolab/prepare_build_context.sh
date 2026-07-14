#!/bin/bash
# Stage the build context for the idrobolab container. Run from this directory,
# then build with docker/podman (see README) or the .def.
#
# Unlike another image's recipe, requirements-idrobolab.txt is HAND-MAINTAINED
# (its packages — nionswift, ptyrad, hiphive, pymatgen, fairchem, … — are not
# in the ROCm dev venv, so there is nothing to scrape). This script only stages
# the three editable source trees the image installs from /opt/src:
#   gpaw (<username> fork, a branch), gpaw-weaver, abTEM.
set -euo pipefail
cd "$(dirname "$0")"

CODE_DIR=${CODE_DIR:-/workspaces/code}
EXCLUDES=(.git build __pycache__ '*.so' '*.egg-info' .venv .pytest_cache)

mkdir -p src
for repo in gpaw gpaw-weaver abTEM; do
    rm -rf "src/${repo}"
    mkdir -p "src/${repo}"
    tar_excludes=()
    for pat in "${EXCLUDES[@]}"; do
        tar_excludes+=(--exclude="$pat")
    done
    tar -C "${CODE_DIR}/${repo}" "${tar_excludes[@]}" -cf - . \
        | tar -C "src/${repo}" -xf -
done
find src -xtype l -delete   # drop symlinks left dangling by the excludes

echo "Build context staged under ./src ($(du -sh src | cut -f1))"
echo "Next: podman build -t idrobolab:latest .   (or ./publish.sh)"
