#!/bin/bash
# Archive the tracked files of a git checkout, with those of its initialised submodules and
# without .git, as $SOURCES_DIR/<name>.tar.gz with every path under <name>/. The archive
# holds the files as the build used them, so a patch applied to a tracked file is in it.
# It fails when an initialised submodule contributes no file to the archive. Submodules
# the build never initialised stay empty directories; they are not part of the build.
#
# Usage: keep-git-source.sh <checkout dir> <name-version>
set -euo pipefail

dir=${1:?usage: keep-git-source.sh <checkout dir> <name-version>}
name=${2:?usage: keep-git-source.sh <checkout dir> <name-version>}
: "${SOURCES_DIR:?}"
archive="${SOURCES_DIR}/${name}.tar.gz"

mkdir -p "$SOURCES_DIR"
git -C "$dir" ls-files -z --recurse-submodules \
    | tar --null -C "$dir" -T - --transform "s,^,${name}/," -czf "$archive"

members=$(tar tzf "$archive")
# Assigned first: a failing git here must stop the script, which a process substitution would not.
initialised=$(git -C "$dir" submodule foreach --quiet --recursive 'echo "$displaypath"')
while IFS= read -r path; do
    [ -n "$path" ] || continue
    prefix="${name}/${path}/"
    if ! awk -v p="$prefix" 'index($0, p) == 1 && length($0) > length(p) { found = 1; exit } END { exit !found }' <<< "$members"; then
        echo "ERROR: submodule ${path} of ${dir} is initialised but ${archive} holds no file of it" >&2
        exit 1
    fi
done <<< "$initialised"
