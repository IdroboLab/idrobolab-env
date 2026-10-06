#!/bin/bash
# sync-nersc.sh — refresh the vendored copy of NERSC's agent baseline.
#
#     perlmutter/agents/sync-nersc.sh
#
# Downloads the files of https://github.com/NERSC/coding-agents at the default
# branch's HEAD into nersc/ (same paths as upstream), byte for byte, and records
# the upstream commit in nersc/UPSTREAM. Prints "up to date" when the vendored
# files already match, otherwise the files that changed. Needs only git, cmp
# and coreutils; the nersc-agents-sync workflow runs it weekly and opens a pull
# request on a change. It is the only thing that edits nersc/.
#
# UPSTREAM is rewritten only when a vendored file changed, so an upstream commit
# that touches only NERSC's READMEs causes no change here. It then names the
# upstream commit at which the files last changed.
set -euo pipefail

REPO=https://github.com/NERSC/coding-agents
FILES="LICENSE claude/.claude/CLAUDE.md codex/.codex/AGENTS.md"
DEST=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/nersc

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 "$REPO" "$TMP/up"
sha=$(git -C "$TMP/up" rev-parse HEAD)
date=$(TZ=UTC git -C "$TMP/up" log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd)

changed=()
for f in $FILES; do
    if ! cmp -s "$TMP/up/$f" "$DEST/$f"; then
        mkdir -p "$DEST/$(dirname "$f")"
        cp "$TMP/up/$f" "$DEST/$f"
        changed+=("nersc/$f")
    fi
done

if [ ${#changed[@]} -eq 0 ]; then
    echo "up to date (NERSC/coding-agents $sha)"
    exit 0
fi

cat > "$DEST/UPSTREAM" <<EOT
repo: $REPO
commit: $sha
date: $date (commit date, UTC)
EOT
echo "updated to NERSC/coding-agents $sha; changed:"
printf '  %s\n' "${changed[@]}" nersc/UPSTREAM
