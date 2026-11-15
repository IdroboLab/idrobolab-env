#!/bin/bash
# install-uv.sh — install or update uv in the shared project bin dir with
# group-correct permissions. Run on a Perlmutter login node; idempotent —
# re-run it to update uv (use this INSTEAD of `uv self update`, which
# replaces the binary with the personal group and umask mode, cutting the
# rest of the project off — exactly the failure this script exists to
# prevent; `cp -p` from a home directory does the same).
#
# The project group is $NERSC_PROJECT, matching env.sh.
set -euo pipefail

PROJECT="${NERSC_PROJECT:?export NERSC_PROJECT=<project> (setup-user.sh writes it into your shell profile)}"
BIN_DIR="/global/common/software/${PROJECT}/bin"

mkdir -p "$BIN_DIR"
# setgid so future files inherit the project group (cp -p and some
# installers still override it, hence the explicit fixes below)
chgrp "$PROJECT" "$BIN_DIR" 2>/dev/null \
    || echo "warning: could not chgrp $BIN_DIR to $PROJECT (not the owner?)" >&2
chmod g+rxs "$BIN_DIR"

# UV_NO_MODIFY_PATH: do not edit the running user's shell rc files —
# env.sh already puts $BIN_DIR on PATH for the whole project.
curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR="$BIN_DIR" UV_NO_MODIFY_PATH=1 sh

# group-fix everything the installer wrote (uv, uvx, and its env helper
# scripts if present)
for f in "$BIN_DIR"/uv "$BIN_DIR"/uvx "$BIN_DIR"/env "$BIN_DIR"/env.fish; do
    [ -e "$f" ] || continue
    chgrp "$PROJECT" "$f" 2>/dev/null || true
    chmod g+rX "$f"
done

# verify: everything in the bin dir must be project-group-readable
bad=$(find "$BIN_DIR" \( ! -group "$PROJECT" -o ! -perm -g+r \) -print -quit)
if [ -n "$bad" ]; then
    echo "WARNING: not usable by group $PROJECT: $bad" >&2
    echo "         (fix by its owner: chgrp $PROJECT <file> && chmod g+rX <file>)" >&2
    exit 1
fi

echo ">> $("$BIN_DIR"/uv --version) in $BIN_DIR — group-$PROJECT verified"
