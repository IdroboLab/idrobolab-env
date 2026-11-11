# Delta shell environment for the idrobolab container stack.
# Source it from ~/.bashrc:
#
#     [ -r "$HOME/idrobolab-env/delta/env.sh" ] && . "$HOME/idrobolab-env/delta/env.sh"
#
# Safe to source unconditionally: it is silent, idempotent, does nothing where
# $SCRATCH_BASE is unset, and never sets `set -e` or calls `exit` (either would
# kill the login shell). Set IDROBOLAB_ENV_VERBOSE=1 before sourcing to see
# what it did.
#
# Do NOT `chmod +x` this file: it is meant to be sourced, not run.

# Caches go to personal scratch, off the home quota. Delta defines
# $SCRATCH_BASE (/scratch/<account>) and no $SCRATCH; personal scratch is
# $SCRATCH_BASE/$USER. The file acts only where $SCRATCH_BASE is set, so
# nothing lands at the filesystem root. Pre-set values are respected.
if [ -n "${SCRATCH_BASE:-}" ]; then
    _idrobolab_env_scratch="${SCRATCH_BASE}/${USER:-$(id -un)}"
    : "${APPTAINER_CACHEDIR:=${_idrobolab_env_scratch}/.apptainer}"
    : "${UV_CACHE_DIR:=${_idrobolab_env_scratch}/uv-cache}"
    export APPTAINER_CACHEDIR UV_CACHE_DIR
    unset _idrobolab_env_scratch
fi

# Diagnostics go to stderr, and only in an interactive shell: ~/.bashrc is
# also sourced for the remote end of scp/rsync/`ssh host cmd`, and anything
# written to stdout there corrupts the transfer.
if [ "${IDROBOLAB_ENV_VERBOSE:-0}" = "1" ] && [ -n "${PS1:-}" ]; then
    echo "idrobolab-env/delta:" >&2
    echo "  SCRATCH_BASE       ${SCRATCH_BASE:-<unset: nothing set>}" >&2
    echo "  APPTAINER_CACHEDIR ${APPTAINER_CACHEDIR:-<unset>}" >&2
    echo "  UV_CACHE_DIR       ${UV_CACHE_DIR:-<unset>}" >&2
fi
