#!/bin/bash
# Print the recipe hash of a recipe directory (default: the directory of this script): the
# sha256 of `git ls-files -s` for the directory, without its README.md (not part of the
# build context), or the string `dirty` when `git status --porcelain` shows any change there.
# prepare_build_context.sh and publish.sh both call it, so the rule lives once.
set -euo pipefail
dir=${1:-$(dirname "$0")}

if [ -n "$(git -C "$dir" status --porcelain -- .)" ]; then
    echo dirty
else
    git -C "$dir" ls-files -s -- . | grep -v -P '\tREADME\.md$' | sha256sum | cut -d' ' -f1
fi
