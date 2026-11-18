#!/bin/bash
# Archive the tracked files of a git checkout, with those of its initialised submodules and
# without .git, as $SOURCES_DIR/<name>.tar.gz with every path under <name>/. The archive
# holds the files as the build used them, so a patch applied to a tracked file is in it.
#
# Usage: keep-git-source.sh <checkout dir> <name-version>
set -euo pipefail

dir=${1:?usage: keep-git-source.sh <checkout dir> <name-version>}
name=${2:?usage: keep-git-source.sh <checkout dir> <name-version>}
: "${SOURCES_DIR:?}"

mkdir -p "$SOURCES_DIR"
git -C "$dir" ls-files -z --recurse-submodules \
    | tar --null -C "$dir" -T - --transform "s,^,${name}/," -czf "${SOURCES_DIR}/${name}.tar.gz"
