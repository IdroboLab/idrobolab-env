#!/bin/bash
# Stage the build context for the idrobolab container. Run from this directory,
# then build with docker/podman (see README).
#
# Unlike another image's recipe, requirements-idrobolab.txt is HAND-MAINTAINED
# (its packages — nionswift, ptyrad, hiphive, pymatgen, fairchem, … — are not
# in the ROCm dev venv, so there is nothing to scrape). This script only stages
# the three editable source trees the image installs from /opt/src:
#   gpaw (its MASTER branch, via git archive — not the working tree;
#   GPAW_REF=<ref> overrides), gpaw-weaver, abTEM.
set -euo pipefail
cd "$(dirname "$0")"

CODE_DIR=${CODE_DIR:-/workspaces/code}
EXCLUDES=(.git build __pycache__ '*.so' '*.egg-info' .venv .pytest_cache)

mkdir -p src

# GPAW: staged from its MASTER branch (the committed tree, via git archive),
# NOT the working tree — the image always carries vanilla gpaw/master no
# matter which branch the dev checkout is on. Branches run via a bind mount
# over /opt/src/gpaw. Deliberate branch build: GPAW_REF=<ref> ./prepare_build_context.sh
# Refresh master first when needed:
#   git -C "$CODE_DIR/gpaw" fetch upstream master:master
GPAW_REF=${GPAW_REF:-master}
rm -rf src/gpaw
mkdir -p src/gpaw
git -C "${CODE_DIR}/gpaw" archive "${GPAW_REF}" | tar -xf - -C src/gpaw
echo "gpaw staged from ${GPAW_REF} ($(git -C "${CODE_DIR}/gpaw" log -1 --format='%h %cs' "${GPAW_REF}"))"

for repo in gpaw-weaver abTEM; do
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
