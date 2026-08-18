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
    export PODMAN_STORE="/global/cfs/cdirs/${NERSC_PROJECT}/podman-hpc"
    export PODMAN_STORE_RO="/dvs_ro/cfs/cdirs/${NERSC_PROJECT}/podman-hpc"

    # Where podman-hpc looks for images beyond its own store.
    #
    # Set only when unset, so re-sourcing is a no-op and an existing value you
    # set deliberately wins. Deliberately does NOT append: the separator for
    # listing several stores in this variable is not documented by NERSC and
    # the single-store case is the one that is actually exercised. If you need
    # more than one, set the variable yourself after sourcing this file.
    if [ -z "${PODMANHPC_ADDITIONAL_STORES:-}" ]; then
        export PODMANHPC_ADDITIONAL_STORES="$PODMAN_STORE_RO"
    fi

    # Convenience refs so job scripts and one-liners can stay short.
    export IDROBOLAB_IMAGE="${IDROBOLAB_IMAGE:-ghcr.io/<username>/idrobolab:latest}"
    export OTHERIMAGE_IMAGE="${OTHERIMAGE_IMAGE:-ghcr.io/<username>/otherimage:latest}"

    if [ "${HPCENVS_ENV_VERBOSE:-0}" = "1" ]; then
        echo "hpcenvs/perlmutter: project=$NERSC_PROJECT"
        echo "  PODMAN_STORE               $PODMAN_STORE"
        echo "  PODMANHPC_ADDITIONAL_STORES $PODMANHPC_ADDITIONAL_STORES"
    fi
fi

# --- optional, deliberately left commented --------------------------------
#
# Move podman-hpc's LOCAL build store off $HOME. Worth doing if `podman-hpc
# info` shows a graphRoot under ~/.local/share/containers: that store has no
# purge policy and a CUDA image will eat into the 40 GB home quota. Enabling
# it makes previously built local images invisible until rebuilt or migrated,
# so flip it deliberately, not by default.
#
export PODMANHPC_GRAPH_ROOT="${SCRATCH}/podman-hpc/storage"
export PODMANHPC_RUN_ROOT="${SCRATCH}/podman-hpc/run"
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
