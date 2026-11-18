#!/bin/bash
# Check that $SOURCES_DIR holds exactly one <component>-* archive for each component named
# on the command line, then write $SOURCES_DIR/SHA256SUMS over all the files in it. The
# build fails when an archive is missing, so the sources image never lacks a component.
#
# Usage: finish-sources.sh <component> [<component> ...]
set -euo pipefail
export LC_ALL=C   # the order of the glob below, and so of SHA256SUMS

: "${SOURCES_DIR:?}"
cd "$SOURCES_DIR"

for name in "$@"; do
    found=( "${name}"-* )
    if [ "${#found[@]}" -ne 1 ] || [ ! -f "${found[0]}" ]; then
        echo "ERROR: ${SOURCES_DIR} needs exactly one ${name}-* archive, found: ${found[*]}" >&2
        exit 1
    fi
done

rm -f SHA256SUMS
sha256sum -- * > SHA256SUMS
