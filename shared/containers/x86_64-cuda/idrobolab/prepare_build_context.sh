#!/bin/bash
# Stage the build context for the idrobolab container. Run from this directory,
# then build with docker/podman (see README).
#
# requirements-idrobolab.txt is HAND-MAINTAINED
# (its packages — nionswift, ptyrad, hiphive, pymatgen, fairchem, … — are not
# in the maintainer's ROCm dev venv, so no pins are scraped from it). This script only stages
# the three editable source trees the image installs from /opt/src, each from
# committed files via git archive, never from the working tree. The only input is
# sources.txt (`<name> <full commit SHA>` per tree): a commit that is missing from the
# checkout, or on no remote-tracking branch, fails the staging, so every tree of the image
# is public and reproducible. A development build edits sources.txt, which makes the recipe
# `dirty` (recipe-hash.sh) and so never a release candidate.
# The image is public, so nothing untracked may reach it: a working tree holds
# agent session data (.claude/), other branches' worktrees (.worktrees/),
# caches and local scratch files.
#
# It also stages lammps-gpu-selftest.sh from core/lammps/ (the vendored hpcenv-core)
# into this directory, where the Dockerfile COPYs it; the staged file is git-ignored,
# and publish.sh refuses to build when it is missing or differs from the core copy.
set -euo pipefail
cd "$(dirname "$0")"

CODE_DIR=${CODE_DIR:-/workspaces/code}

mkdir -p src

cp ../../../../core/lammps/lammps-gpu-selftest.sh lammps-gpu-selftest.sh

recipe_hash=$(./recipe-hash.sh)
build_id=$(date -u +%Y%m%dT%H%M%SZ)

pairs=()
while read -r name sha || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    repo="${CODE_DIR}/${name}"
    if ! [[ $sha =~ ^[0-9a-f]{40}$ ]]; then
        echo "ERROR: sources.txt: '${sha}' for ${name} is not a full commit SHA" >&2
        exit 1
    fi
    if ! git -C "$repo" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        echo "ERROR: ${name}: commit ${sha} is not in ${repo}" >&2
        exit 1
    fi
    if [ -z "$(git -C "$repo" branch -r --contains "$sha")" ]; then
        echo "ERROR: ${name}: commit ${sha} is on no remote-tracking branch (push it first)" >&2
        exit 1
    fi
    rm -rf "src/${name}"
    mkdir -p "src/${name}"
    git -C "$repo" archive "$sha" | tar -xf - -C "src/${name}"
    pairs+=("$name" "$sha")
    echo "${name} staged from ${sha} ($(git -C "$repo" log -1 --format='%cs' "$sha"))"
done < sources.txt
if [ ${#pairs[@]} -eq 0 ]; then
    echo "ERROR: sources.txt names no source tree" >&2
    exit 1
fi

python3 -c 'import json, sys
version, recipe_hash, build_id, *pairs = sys.argv[1:]
print(json.dumps({"image": "idrobolab", "version": int(version), "recipe_hash": recipe_hash,
                  "build_id": build_id, "sources": dict(zip(pairs[::2], pairs[1::2]))}))' \
    "$(cat VERSION)" "$recipe_hash" "$build_id" "${pairs[@]}" > src/manifest.json
echo "manifest: version $(cat VERSION), recipe hash ${recipe_hash}, build id ${build_id}"

echo "Build context staged under ./src ($(du -sh src | cut -f1))"
echo "Next: ./publish.sh"
