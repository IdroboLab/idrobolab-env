#!/bin/bash
# Stage the build context for the idrobolab container. Run from this directory,
# then build with docker/podman (see README).
#
# Unlike another image's recipe, requirements-idrobolab.txt is HAND-MAINTAINED
# (its packages — nionswift, ptyrad, hiphive, pymatgen, fairchem, … — are not
# in the ROCm dev venv, so there is nothing to scrape). This script only stages
# the three editable source trees the image installs from /opt/src, each from
# committed files via git archive, never from the working tree:
#   gpaw (its MASTER branch; GPAW_REF=<ref> overrides), and gpaw-weaver and
#   abTEM (the commit each dev checkout has checked out).
# The image is public, so nothing untracked may reach it: a working tree holds
# agent session data (.claude/), other branches' worktrees (.worktrees/),
# caches and local scratch files.
set -euo pipefail
cd "$(dirname "$0")"

CODE_DIR=${CODE_DIR:-/workspaces/code}

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
    git -C "${CODE_DIR}/${repo}" archive HEAD | tar -xf - -C "src/${repo}"
    branch=$(git -C "${CODE_DIR}/${repo}" branch --show-current)
    dirty=$(git -C "${CODE_DIR}/${repo}" status --porcelain)
    echo "${repo} staged from HEAD of branch '${branch:-<detached HEAD>}'" \
        "($(git -C "${CODE_DIR}/${repo}" log -1 --format='%h %cs'))${dirty:+ — note: uncommitted changes and untracked files in the checkout are NOT included}"
done

echo "Build context staged under ./src ($(du -sh src | cut -f1))"
echo "Next: podman build -t idrobolab:latest .   (or ./publish.sh)"
