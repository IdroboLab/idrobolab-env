# Perlmutter shell environment for the <project> container stack.
# Source it from ~/.bashrc:
#
#     [ -r "$HOME/hpcenvs/perlmutter/env.sh" ] && . "$HOME/hpcenvs/perlmutter/env.sh"
#
# Safe to source unconditionally: it is silent, idempotent, does nothing off
# Perlmutter, and never sets `set -e` or calls `exit` (either would kill the
# login shell). Set HPCENVS_ENV_VERBOSE=1 before sourcing to see what it did.
#
# Do NOT `chmod +x` this file — it is meant to be sourced, not run.

# Only act on Perlmutter. NERSC_HOST is set site-wide; the directory check is
# a fallback for shells that start before the site profile.
if [ "${NERSC_HOST:-}" = "perlmutter" ] || [ -d /global/cfs/cdirs ]; then

    # Project whose CFS directory holds the shared podman-hpc store. Override
    # by exporting NERSC_PROJECT before sourcing.
    : "${NERSC_PROJECT:=<project>}"
    export NERSC_PROJECT

    # Two paths to the same store, and the distinction matters:
    #   PODMAN_STORE     writable /global/cfs path — pull/build into this
    #   PODMAN_STORE_RO  /dvs_ro read-only mirror — read from this in jobs
    # DVS caches reads for ~30 s, which is ideal for immutable squashed images
    # and the reason compute-node startup is faster through it.
    # The squashed images sit in an `images` subdirectory — that is the path
    # update-image.sh passes to --squash-dir and the one podman-hpc migrates
    # into. Derive the read path from the writable one instead of writing the
    # tail out twice: maintained separately they drifted, PODMAN_STORE_RO kept
    # pointing a level too high, and a job sourcing this file could not resolve
    # the image at all.
    export PODMAN_STORE="/global/cfs/cdirs/${NERSC_PROJECT}/podman-hpc/images"
    export PODMAN_STORE_RO="/dvs_ro/cfs/${PODMAN_STORE#/global/cfs/}"

    # Keep podman's LOCAL staging store off CFS. It holds a full second copy of
    # every image (20 GB for idrobolab) plus a sqlite database and lock files,
    # none of which belong on a shared filesystem. $SCRATCH is per-user, which
    # removes the multi-user hazard.
    #
    # The node-local default (/tmp/{uid}_hpc/storage) is better still: $SCRATCH
    # is a network filesystem reachable from every node, and a job that runs
    # one container per rank puts every rank's podman on the same store. Unset
    # both to go back to it. Note also that $SCRATCH is purged after 8 weeks
    # without access, which can eat part of the store and leave it wedged —
    # `podman-hpc rmi` and re-pull rather than letting purge do it piecemeal.
    #
    # Guarded: unset $SCRATCH would expand these to /podman-hpc/storage at the
    # filesystem root.
    if [ -n "${SCRATCH:-}" ]; then
        export PODMANHPC_GRAPH_ROOT="${SCRATCH}/podman-hpc/storage"
        export PODMANHPC_RUN_ROOT="${SCRATCH}/podman-hpc/run"
    fi

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
    _hpcenvs_cur=${PODMANHPC_ADDITIONAL_STORES:-}
    _hpcenvs_adopt=0
    if [ -z "$_hpcenvs_cur" ]; then
        _hpcenvs_adopt=1
    elif [ "$_hpcenvs_cur" = "${HPCENVS_DERIVED_STORE_RO:-}" ]; then
        _hpcenvs_adopt=1
    else
        case "$_hpcenvs_cur" in
            /dvs_ro/cfs/cdirs/*/podman-hpc|/dvs_ro/cfs/cdirs/*/podman-hpc/images)
                _hpcenvs_adopt=1 ;;
        esac
    fi
    if [ "$_hpcenvs_adopt" = 1 ]; then
        export PODMANHPC_ADDITIONAL_STORES="$PODMAN_STORE_RO"
    fi
    export HPCENVS_DERIVED_STORE_RO="$PODMAN_STORE_RO"
    unset _hpcenvs_cur _hpcenvs_adopt

    # Convenience refs so job scripts and one-liners can stay short.
    export IDROBOLAB_IMAGE="${IDROBOLAB_IMAGE:-ghcr.io/<username>/idrobolab:latest}"
    export OTHERIMAGE_IMAGE="${OTHERIMAGE_IMAGE:-ghcr.io/<username>/otherimage:latest}"

    # Diagnostics go to stderr, and only in an interactive shell. ~/.bashrc is
    # also sourced for the remote end of scp/rsync/`ssh host cmd`; anything
    # written to stdout there corrupts the protocol stream and the transfer
    # fails with a confusing "protocol error".
    if [ "${HPCENVS_ENV_VERBOSE:-0}" = "1" ] && [ -n "${PS1:-}" ]; then
        echo "hpcenvs/perlmutter: project=$NERSC_PROJECT" >&2
        echo "  PODMAN_STORE                $PODMAN_STORE" >&2
        echo "  PODMANHPC_ADDITIONAL_STORES $PODMANHPC_ADDITIONAL_STORES" >&2
        echo "  PODMANHPC_GRAPH_ROOT        ${PODMANHPC_GRAPH_ROOT:-<unset: node-local default>}" >&2
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
