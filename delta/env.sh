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

# Caches go to scratch, off the home quota. Delta defines $SCRATCH_BASE
# (/scratch/<account>) and no $SCRATCH; personal scratch is $SCRATCH_BASE/$USER.
# The file acts only where $SCRATCH_BASE is set, so nothing lands at the
# filesystem root. Pre-set values are respected.
if [ -n "${SCRATCH_BASE:-}" ]; then
    _idrobolab_env_scratch="${SCRATCH_BASE}/${USER:-$(id -un)}"
    : "${APPTAINER_CACHEDIR:=${_idrobolab_env_scratch}/.apptainer}"
    export APPTAINER_CACHEDIR

    # uv's cache is shared by the project: $SCRATCH_BASE/uv-cache, which an
    # admin creates once as a setgid directory with a default ACL
    # (docs/delta/README.md), so the files every member's uv writes there are
    # group-writable whatever that member's umask. It is used only once it
    # exists and is writable: a cache directory uv creates by itself is
    # private to its creator. Until then the cache is on personal scratch.
    #
    # With the shared cache uv copies packages into an environment instead of
    # hardlinking them: a hardlinked file is the cache's own file, and editing
    # it in one environment would change it for every member.
    if [ -d "${SCRATCH_BASE}/uv-cache" ] && [ -w "${SCRATCH_BASE}/uv-cache" ]; then
        : "${UV_CACHE_DIR:=${SCRATCH_BASE}/uv-cache}"
        : "${UV_LINK_MODE:=copy}"
        export UV_LINK_MODE
    else
        : "${UV_CACHE_DIR:=${_idrobolab_env_scratch}/uv-cache}"
    fi
    export UV_CACHE_DIR
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
    echo "  UV_LINK_MODE       ${UV_LINK_MODE:-<unset: uv default>}" >&2
fi
