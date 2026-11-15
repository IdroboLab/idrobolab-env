# Delta shell environment for the idrobolab container stack.
# Source it from ~/.bashrc, below the line that names your Delta project (the
# <project> of your <project>-delta-cpu and <project>-delta-gpu accounts, see
# the `accounts` command):
#
#     export DELTA_PROJECT=<project>
#     [ -r "$HOME/idrobolab-env/delta/env.sh" ] && . "$HOME/idrobolab-env/delta/env.sh"
#
# delta/helpers/setup-user.sh writes both lines for you.
#
# Safe to source unconditionally: it is silent, idempotent, does nothing while
# DELTA_PROJECT is unset or names no directory under /scratch, and never sets
# `set -e` or calls `exit` (either would kill the login shell). Set
# IDROBOLAB_ENV_VERBOSE=1 before sourcing to see what it did.
#
# Bash only: it uses BASH_SOURCE, and core/shell/accounts.sh, which it sources, is bash.
#
# Do NOT `chmod +x` this file: it is meant to be sourced, not run.

# The directory test keeps the file inert off Delta and for a mistyped
# project. Pre-set values are respected throughout.
if [ -n "${DELTA_PROJECT:-}" ] && [ -d "/scratch/${DELTA_PROJECT}" ]; then

    # The project's scratch and projects directories, which the job templates
    # and get-image.sh read. Delta sets $SCRATCH only inside
    # jobs, so personal scratch is $SCRATCH_BASE/$USER everywhere.
    : "${SCRATCH_BASE:=/scratch/${DELTA_PROJECT}}"
    : "${PROJECTS_BASE:=/projects/${DELTA_PROJECT}}"
    export SCRATCH_BASE PROJECTS_BASE

    # Caches go to scratch, off the home quota.
    _idrobolab_env_scratch="${SCRATCH_BASE}/${USER:-$(id -un)}"
    : "${APPTAINER_CACHEDIR:=${_idrobolab_env_scratch}/.apptainer}"
    export APPTAINER_CACHEDIR

    # uv's cache is shared by the project: $SCRATCH_BASE/uv-cache, which an
    # admin creates once as a setgid directory with a default ACL
    # (docs/delta/README.md), so what every member's uv writes there is
    # writable by the group whatever that member's umask. It is used only once
    # it exists and is writable for you: a cache directory uv creates by itself
    # is not writable by the other members. Until then the cache is on
    # personal scratch.
    #
    # With the shared cache uv copies packages into an environment. A
    # hardlinked file (the default of older uv versions) is the cache's own
    # file, and editing it in one environment would change it for every member.
    if [ -z "${UV_CACHE_DIR:-}" ]; then
        if [ -d "${SCRATCH_BASE}/uv-cache" ] && [ -w "${SCRATCH_BASE}/uv-cache" ]; then
            UV_CACHE_DIR="${SCRATCH_BASE}/uv-cache"
            : "${UV_LINK_MODE:=copy}"
            export UV_LINK_MODE
        else
            UV_CACHE_DIR="${_idrobolab_env_scratch}/uv-cache"
        fi
    fi
    export UV_CACHE_DIR
    unset _idrobolab_env_scratch

    # The project's shared bin directory (the uv binary an admin installs
    # there, docs/delta/README.md). Prepended so project tools win over system
    # ones; guarded so re-sourcing never grows PATH, and skipped until the
    # directory exists.
    _idrobolab_env_bin="${PROJECTS_BASE}/software/bin"
    if [ -d "$_idrobolab_env_bin" ]; then
        case ":$PATH:" in
            *":${_idrobolab_env_bin}:"*) ;;
            *) PATH="${_idrobolab_env_bin}:$PATH"; export PATH ;;
        esac
    fi
    unset _idrobolab_env_bin

    # sbatch and salloc add -A, so that `sbatch template.sbatch` needs no edit of the
    # template's --account line (core/shell/accounts.sh; its header and core/README.md
    # describe the variables). The accounts are <project>-delta-cpu and <project>-delta-gpu
    # (the `accounts` command lists them); a job counts as a GPU job when it asks for a
    # partition `gpu*` or for GPUs. Exported: the template check and the scripts that source
    # accounts.sh (jobs/interactive_gpu.sh, get-image.sh) read them.
    # They are set from the cluster's rules and the project variable each time this file is
    # sourced, so a value set beforehand is not kept.
    export HPCENV_ACCOUNT_PROJECT="$DELTA_PROJECT"
    export HPCENV_ACCOUNT_CPU='{project}-delta-cpu'
    export HPCENV_ACCOUNT_GPU='{project}-delta-gpu'
    export HPCENV_ACCOUNT_GPU_PARTITIONS='gpu*'
    _idrobolab_env_accounts="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/../core/shell/accounts.sh"
    # shellcheck source=../core/shell/accounts.sh
    if [ -r "$_idrobolab_env_accounts" ]; then . "$_idrobolab_env_accounts"; fi
    unset _idrobolab_env_accounts
fi

# Diagnostics go to stderr, and only in an interactive shell: ~/.bashrc is
# also sourced for the remote end of scp/rsync/`ssh host cmd`, and anything
# written to stdout there corrupts the transfer.
if [ "${IDROBOLAB_ENV_VERBOSE:-0}" = "1" ] && [ -n "${PS1:-}" ]; then
    echo "idrobolab-env/delta:" >&2
    echo "  DELTA_PROJECT      ${DELTA_PROJECT:-<unset: nothing set>}" >&2
    echo "  SCRATCH_BASE       ${SCRATCH_BASE:-<unset>}" >&2
    echo "  PROJECTS_BASE      ${PROJECTS_BASE:-<unset>}" >&2
    echo "  APPTAINER_CACHEDIR ${APPTAINER_CACHEDIR:-<unset>}" >&2
    echo "  UV_CACHE_DIR       ${UV_CACHE_DIR:-<unset>}" >&2
    echo "  UV_LINK_MODE       ${UV_LINK_MODE:-<unset: uv default>}" >&2
fi
