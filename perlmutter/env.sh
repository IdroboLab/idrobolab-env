# Perlmutter shell environment for the <project> container stack.
# Source it from ~/.bashrc:
#
#     [ -r "$HOME/idrobolab-env/perlmutter/env.sh" ] && . "$HOME/idrobolab-env/perlmutter/env.sh"
#
# perlmutter/helpers/setup-user.sh writes that line for you.
#
# Safe to source unconditionally: it is silent, idempotent, does nothing off
# Perlmutter, and never sets `set -e` or calls `exit` (either would kill the
# login shell). Set IDROBOLAB_ENV_VERBOSE=1 before sourcing to see what it did.
#
# Do NOT `chmod +x` this file — it is meant to be sourced, not run.

# Only act on Perlmutter. NERSC_HOST is set site-wide; the directory check is
# a fallback for shells that start before the site profile.
if [ "${NERSC_HOST:-}" = "perlmutter" ] || [ -d /global/cfs/cdirs ]; then

    # Project whose CFS directory holds the shared podman-hpc store. Override
    # by exporting NERSC_PROJECT before sourcing.
    : "${NERSC_PROJECT:=<project>}"
    export NERSC_PROJECT

    # Root of the project's CFS directory. Everything group-shared lives below
    # it (podman-hpc/, projects/). Override by exporting it before sourcing;
    # it must lie under /global/cfs/, since PODMAN_STORE_RO is derived from it
    # by swapping that prefix for /dvs_ro/cfs/.
    : "${IDROBOLAB_ENV_PROJECT_ROOT:=/global/cfs/cdirs/${NERSC_PROJECT}}"
    export IDROBOLAB_ENV_PROJECT_ROOT

    # Two paths to the same store, and the distinction matters:
    #   PODMAN_STORE     writable path under the project root — pull/build into this
    #   PODMAN_STORE_RO  /dvs_ro read-only mirror — read from this in jobs
    # DVS caches reads for ~30 s, which is ideal for immutable squashed images
    # and the reason compute-node startup is faster through it.
    # The squashed images sit in an `images` subdirectory — that is the path
    # update-image.sh passes to --squash-dir and the one podman-hpc migrates
    # into. Derive the read path from the writable one instead of writing the
    # tail out twice: maintained separately they drifted, PODMAN_STORE_RO kept
    # pointing a level too high, and a job sourcing this file could not resolve
    # the image at all.
    export PODMAN_STORE="${IDROBOLAB_ENV_PROJECT_ROOT}/podman-hpc/images"
    export PODMAN_STORE_RO="/dvs_ro/cfs/${PODMAN_STORE#/global/cfs/}"

    # Keep podman's LOCAL staging store off CFS. It holds a full second copy of
    # every image (20 GB for idrobolab) plus a sqlite database and lock files,
    # none of which belong on a shared filesystem. $SCRATCH is per-user, which
    # removes the multi-user hazard.
    #
    # The node-local default is better still: $SCRATCH
    # is a network filesystem reachable from every node, and a job that runs
    # one container per rank puts every rank's podman on the same store. Unset
    # both to go back to it. Note also that $SCRATCH is purged after 8 weeks
    # without access, which can eat part of the store and leave it wedged —
    # `podman-hpc rmi` and re-pull rather than letting purge do it piecemeal.
    #
    # Guarded: unset $SCRATCH would expand these to /podman-hpc/storage at the
    # filesystem root.
    # DISABLED 2026-08-18 after this broke image migration outright. Pointing
    # the graph root at $SCRATCH (Lustre) let `podman-hpc pull` download all
    # 19 GB and then fail to squash, every time:
    #
    #     ERROR:root:Squash Failed
    #     Creating 4.0 filesystem on /sqout/<link>.squash ...
    #     [/                              ] 0/2   0%
    #     "/" is not a shared mount, this could cause issues or missing mounts
    #     Network file system detected as backing store. Enforcing overlay
    #       option `force_mask="700"`
    #     Unrecognised xattr prefix (null)      (x8)
    #
    # `0/2` is the giveaway: mksquashfs was handed a rootfs with two entries in
    # it. The squash step runs `podman run --root <graph_root> ... <img> /`, and
    # a fuse-overlayfs graph root on Lustre -- with force_mask enforced and
    # non-shared mount propagation for rootless podman -- never assembles into a
    # usable rootfs. The xattr errors are a symptom of the same thing. There is
    # no way around it: podman-hpc hardcodes its mksquashfs options
    # (migrate2scratch.py: mksq_options), so `-no-xattrs` cannot be passed.
    #
    # Leave both unset for podman-hpc's node-local default
    # (observed on a login node: /images/<uid>_hpc/storage -- NERSC provisions
    # /images as node-local space for exactly this; upstream's default is
    # /tmp/{uid}_hpc/storage). That is what NERSC ships and what works. The
    # squash STORE stays on CFS -- that part is fine and is what jobs read.
    # $SCRATCH is no better than CFS here; both are network filesystems.
    #
    # if [ -n "${SCRATCH:-}" ]; then
    #     export PODMANHPC_GRAPH_ROOT="${SCRATCH}/podman-hpc/storage"
    #     export PODMANHPC_RUN_ROOT="${SCRATCH}/podman-hpc/run"
    # fi

    # Where podman-hpc looks for images beyond its own store.
    #
    # Adopt the derived value when the variable is unset, when it still holds
    # what an earlier source of this file derived, or when it holds a path
    # recognisably one of ours from a previous revision. The store path has
    # already changed more than once; without this a long-lived shell keeps
    # exporting a stale path for its whole life while every new shell gets the
    # right one — which is precisely how a job ends up unable to find an image
    # that `podman-hpc images` shows on the login node. A value set by hand to
    # something unrelated is left alone.
    #
    # Multi-store use is still not supported here: NERSC does not document the
    # separator, so set the variable yourself after sourcing if you need two.
    _idrobolab_env_cur=${PODMANHPC_ADDITIONAL_STORES:-}
    _idrobolab_env_adopt=0
    if [ -z "$_idrobolab_env_cur" ]; then
        _idrobolab_env_adopt=1
    elif [ "$_idrobolab_env_cur" = "${IDROBOLAB_ENV_DERIVED_STORE_RO:-}" ]; then
        _idrobolab_env_adopt=1
    else
        case "$_idrobolab_env_cur" in
            /dvs_ro/cfs/cdirs/*/podman-hpc|/dvs_ro/cfs/cdirs/*/podman-hpc/images)
                _idrobolab_env_adopt=1 ;;
        esac
    fi
    if [ "$_idrobolab_env_adopt" = 1 ]; then
        export PODMANHPC_ADDITIONAL_STORES="$PODMAN_STORE_RO"
    fi
    export IDROBOLAB_ENV_DERIVED_STORE_RO="$PODMAN_STORE_RO"
    unset _idrobolab_env_cur _idrobolab_env_adopt

    # Convenience refs so job scripts and one-liners can stay short.
    export IDROBOLAB_IMAGE="${IDROBOLAB_IMAGE:-ghcr.io/idrobolab/idrobolab:latest}"

    # uv-managed Python interpreters go on /global/common: read-optimized for
    # importing packages, read-only on compute nodes (install from a login
    # node), and shared project-wide so every venv under
    # /global/common/software/<project>/venvs/ symlinks ONE interpreter
    # everyone can read — a venv whose python resolves into someone's $HOME
    # is unusable by the rest of the group. A pre-set value is respected.
    : "${UV_PYTHON_INSTALL_DIR:=/global/common/software/${NERSC_PROJECT}/uv/pythons}"
    export UV_PYTHON_INSTALL_DIR

    # uv's cache must not live under $HOME: the home filesystem does not
    # support the lock uv takes, and every `uv run`/`uvx` on a compute node
    # then dies with "Could not acquire lock ... Unknown error 524" before
    # doing anything. $SCRATCH is per-user and lock-capable. Guarded: unset
    # $SCRATCH would expand to /uv-cache at the filesystem root. Note the
    # purge caveat above applies to this cache too; it is only a cache.
    if [ -n "${SCRATCH:-}" ]; then
        : "${UV_CACHE_DIR:=${SCRATCH}/uv-cache}"
        export UV_CACHE_DIR
    fi

    # Shared project bin dir (the uv binary, small wrappers). Prepended so
    # project tools win over system ones; guarded so re-sourcing never grows
    # PATH, and skipped entirely until the directory exists.
    _idrobolab_env_bin="/global/common/software/${NERSC_PROJECT}/bin"
    if [ -d "$_idrobolab_env_bin" ]; then
        case ":$PATH:" in
            *":${_idrobolab_env_bin}:"*) ;;
            *) PATH="${_idrobolab_env_bin}:$PATH"; export PATH ;;
        esac
    fi
    unset _idrobolab_env_bin

    # Interactive conveniences. Only defined in an interactive shell: aliases
    # are not expanded in non-interactive bash anyway, and this file is also
    # sourced for the remote end of scp/rsync/`ssh host cmd`. Set
    # IDROBOLAB_ENV_ALIASES=0 before sourcing to skip them (e.g. if `q` is already
    # yours). Deliberately written against $SCRATCH and `squeue --me` rather
    # than a hard-coded username, so they are correct for everyone in the
    # project — these started life as one group member's personal aliases.
    if [ "${IDROBOLAB_ENV_ALIASES:-1}" != "0" ] && [ -n "${PS1:-}" ]; then

        # Personal scratch. Guarded: unset $SCRATCH would make `cds` a `cd` to
        # $HOME, which is a silent and confusing wrong answer on a purge-aware
        # filesystem.
        if [ -n "${SCRATCH:-}" ]; then
            alias cds='cd "$SCRATCH"'
        fi

        # Project space on CFS: the shared `projects` directory, which is
        # where group work lives. Export IDROBOLAB_ENV_PROJECT_DIR before sourcing
        # to land somewhere else instead -- your own subdirectory, say
        # (.../projects/<name>) -- and that value is left alone here.
        #
        # Spelled `cdirs`: /global/cfs/projectdirs is a single top-level
        # symlink to it, so both names reach the same directory in a shell,
        # but this is the real one and the only one that exists inside a
        # container unless mounted (jobs/*.sbatch mount both, see
        # jobs/README.md). Landing on the canonical path keeps $PWD -- and
        # anything derived from it -- usable in a container command line.
        : "${IDROBOLAB_ENV_PROJECT_DIR:=${IDROBOLAB_ENV_PROJECT_ROOT}/projects}"
        export IDROBOLAB_ENV_PROJECT_DIR
        alias cdp='cd "$IDROBOLAB_ENV_PROJECT_DIR"'

        # Queue: everything of mine, then filtered by state. `--me` is the
        # portable form of `-u $USER` and needs no per-user edit.
        alias q='squeue --me'
        alias sr='squeue --me -t RUNNING'
        alias sp='squeue --me -t PENDING'
    fi

    # Diagnostics go to stderr, and only in an interactive shell. ~/.bashrc is
    # also sourced for the remote end of scp/rsync/`ssh host cmd`; anything
    # written to stdout there corrupts the protocol stream and the transfer
    # fails with a confusing "protocol error".
    if [ "${IDROBOLAB_ENV_VERBOSE:-0}" = "1" ] && [ -n "${PS1:-}" ]; then
        echo "idrobolab-env/perlmutter: project=$NERSC_PROJECT" >&2
        echo "  PODMAN_STORE                $PODMAN_STORE" >&2
        echo "  PODMANHPC_ADDITIONAL_STORES $PODMANHPC_ADDITIONAL_STORES" >&2
        echo "  PODMANHPC_GRAPH_ROOT        ${PODMANHPC_GRAPH_ROOT:-<unset: node-local default>}" >&2
        echo "  UV_PYTHON_INSTALL_DIR       $UV_PYTHON_INSTALL_DIR" >&2
        echo "  UV_CACHE_DIR                ${UV_CACHE_DIR:-<unset: no \$SCRATCH>}" >&2
    fi
fi

# --- optional, deliberately left commented --------------------------------
#
# Default Slurm account, so `sbatch`/`salloc` need no -A. Left off because
# the two allocations differ by suffix and picking one silently mischarges
# the other kind of job: GPU work needs <project>_g, CPU work needs <project>.
#
#   export SBATCH_ACCOUNT=<project>_g
#   export SALLOC_ACCOUNT=<project>_g
#
# GHCR credentials that survive logout (podman-hpc's default auth.json lives
# in $XDG_RUNTIME_DIR and does not). Point login and pull at a persistent file:
#
#   export REGISTRY_AUTH_FILE="$HOME/.config/containers/auth.json"
