#!/bin/bash
# Pull (or refresh) a container image into the <project> shared podman-hpc store on
# CFS, so it survives $SCRATCH purges and is readable by the whole project.
#
# Run on a Perlmutter LOGIN node — compute nodes have no route to ghcr.io.
#
# Usage:
#   ./update-image.sh                      # idrobolab:latest
#   ./update-image.sh otherimage           # sibling image, same store
#   TAG=v2 ./update-image.sh idrobolab     # a specific tag
#   IMAGE=ghcr.io/someone/thing ./update-image.sh
#   REFRESH=1 ./update-image.sh            # drop the squashed copy first
#
# Afterwards, jobs read the store through the DVS read-only mirror — see
# env.sh, which exports PODMANHPC_ADDITIONAL_STORES for exactly that.
set -euo pipefail

# Defaults match env.sh; sourcing that file first parameterises this script
# (PODMAN_STORE / PODMAN_STORE_RO), and STORE / STORE_RO still win if set.
STORE=${STORE:-${PODMAN_STORE:-/global/cfs/cdirs/<project>/podman-hpc/images}}

# Derive the read path FROM $STORE instead of defaulting it separately. As two
# independent literals they drift — and a stale STORE_RO is invisible here,
# surfacing only as a job that cannot resolve the image. /dvs_ro/cfs mirrors
# /global/cfs, so the tail is identical. An explicit STORE_RO still wins.
if [ -z "${STORE_RO:-}" ]; then
    case "$STORE" in
        /global/cfs/*) STORE_RO="/dvs_ro/cfs/${STORE#/global/cfs/}" ;;
        *)             STORE_RO="$STORE" ;;
    esac
fi

NAME=${1:-idrobolab}
IMAGE=${IMAGE:-ghcr.io/<username>/$NAME}
TAG=${TAG:-latest}
REF="${IMAGE}:${TAG}"
WHOAMI=${USER:-$(id -un)}       # $USER is not set in every batch/container shell

command -v podman-hpc >/dev/null 2>&1 || {
    echo "ERROR: podman-hpc not on PATH — run this on a Perlmutter login node" >&2
    exit 1
}

# Pulls need outbound network; compute nodes do not have it. $SLURM_JOB_ID is
# set inside an allocation (batch or interactive), which is the giveaway.
if [ -n "${SLURM_JOB_ID:-}" ]; then
    echo "ERROR: inside a Slurm allocation (job $SLURM_JOB_ID). Pull from a" >&2
    echo "       login node instead; compute nodes cannot reach the registry." >&2
    exit 1
fi

# The store must be the WRITABLE /global/cfs path. /dvs_ro is read-only by
# design, and a pull aimed at it fails in a confusing way.
case "$STORE" in
    /dvs_ro/*)
        echo "ERROR: STORE points at the read-only DVS mirror ($STORE)." >&2
        echo "       Pull to /global/cfs/... and let jobs read /dvs_ro/cfs/..." >&2
        exit 1 ;;
esac

mkdir -p "$STORE"
[ -w "$STORE" ] || { echo "ERROR: $STORE is not writable by $WHOAMI" >&2; exit 1; }

# --- registry preflight ---------------------------------------------------
# GHCR packages are private until made public by hand, and an anonymous pull
# of a private one fails as "invalid username/password: unauthorized" — which
# looks like a credential bug rather than a visibility setting. Detect that
# here and say something actionable. Non-fatal: skipped if curl is missing,
# and a failed probe never blocks the pull attempt.
case "$IMAGE" in
    ghcr.io/*)
        if command -v curl >/dev/null 2>&1; then
            repo=${IMAGE#ghcr.io/}
            # The token endpoint answers 200 even for a private package (with
            # an errors array instead of a token), and an unauthenticated
            # manifest request answers 401 even for a public one — neither
            # status alone tells you anything. Fetch an anonymous token, then
            # try to actually use it.
            tok=$(curl -sf "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull" \
                      2>/dev/null | sed -n 's/.*"token":"\([^"]*\)".*/\1/p') || tok=""
            if [ -z "$tok" ] || ! curl -sf -o /dev/null \
                    -H "Authorization: Bearer $tok" \
                    "https://ghcr.io/v2/${repo}/tags/list"; then
                echo ">> note: ghcr.io/${repo} is not anonymously readable."
                echo "   Either make the package public, or log in first:"
                echo "     podman-hpc login ghcr.io -u <github-user>"
                echo "   (add --authfile \$HOME/.config/containers/auth.json to keep the"
                echo "    login past logout). Continuing — an existing login may cover it."
            fi
        fi ;;
esac

# --- pull -----------------------------------------------------------------
if [ "${REFRESH:-0}" = "1" ]; then
    echo ">> removing the existing squashed copy of $REF"
    podman-hpc --squash-dir "$STORE" rmi "$REF" || true
fi

# podman-hpc's trace log runs to several hundred lines per pull. It earned its
# keep once — it is how the graph root was spotted sitting on CFS — but it is
# noise by default, so it is opt-in: LOG_LEVEL=trace ./update-image.sh
LOG_LEVEL=${LOG_LEVEL:-}
pull_args=(--squash-dir "$STORE")
if [ -n "$LOG_LEVEL" ]; then
    pull_args=(--log-level "$LOG_LEVEL" "${pull_args[@]}")
fi

# A 20 GB image over a network backing store is a long copy with a real
# failure rate. Blobs that fully landed are reused on a repeat pull ("Checking
# if we can reuse blob"), so a retry is cheaper than starting over — though a
# blob interrupted mid-transfer does restart, since podman reports "partial
# images are disabled". Retry rather than making the caller notice and rerun.
attempts=${RETRIES:-3}
backoff=${RETRY_WAIT:-30}
started=$SECONDS
n=1
while : ; do
    echo ">> pulling $REF into $STORE  (attempt $n/$attempts)"
    if podman-hpc "${pull_args[@]}" pull "$REF"; then
        break
    fi
    if [ "$n" -ge "$attempts" ]; then
        echo "ERROR: pull failed $attempts times — giving up." >&2
        echo "       Fully-fetched blobs are kept, so rerunning resumes." >&2
        echo "       Re-run with LOG_LEVEL=trace to see why, and check the" >&2
        echo "       project CFS quota and whether the graph root sits on a" >&2
        echo "       network filesystem:" >&2
        echo "         podman-hpc info --format '{{.Store.GraphRoot}}'" >&2
        exit 1
    fi
    echo ">> attempt $n failed; retrying in ${backoff}s"
    sleep "$backoff"
    n=$((n + 1))
done
echo ">> pull completed in $((SECONDS - started))s"

# --- provenance -----------------------------------------------------------
# The digest is what identifies the image in a campaign record; :latest moves.
echo ">> digest:"
podman-hpc --squash-dir "$STORE" images --digests | grep -E "REPOSITORY|${IMAGE}" || true

digest=$(podman-hpc --squash-dir "$STORE" inspect --format '{{index .RepoDigests 0}}' \
             "$REF" 2>/dev/null || echo "unknown")
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if printf '%s\t%s\t%s\t%s\n' "$stamp" "$WHOAMI" "$REF" "$digest" \
        >> "$STORE/pull-history.log" 2>/dev/null; then
    echo ">> logged to $STORE/pull-history.log"
fi

# --- footprint ------------------------------------------------------------
# podman keeps TWO copies: the graph-root one it pulled into, and the squashed
# one it migrated to. Only the squashed copy is needed to run a job — that is
# how a collaborator who never pulled can use the store — so a graph root on a
# shared filesystem doubles usage and slows every pull for no benefit.
if [ "${FOOTPRINT:-1}" = "1" ]; then
    graph_root=$(podman-hpc info --format '{{.Store.GraphRoot}}' 2>/dev/null) || graph_root=""
    echo ">> footprint (du on a network filesystem is slow; FOOTPRINT=0 skips it):"
    if [ -n "$graph_root" ] && [ -d "$graph_root" ]; then
        echo "   graph root, not needed by jobs  $(du -sh "$graph_root" 2>/dev/null | cut -f1)  $graph_root"
    fi
    if [ -d "$STORE" ]; then
        echo "   squash store, read by jobs      $(du -sh "$STORE" 2>/dev/null | cut -f1)  $STORE"
    fi
    case "$graph_root" in
        /global/cfs/*|/dvs_ro/*|/global/homes/*)
            echo "   WARNING: the graph root is on a SHARED filesystem. Podman keeps a"
            echo "   sqlite database and lock files there, so concurrent access from"
            echo "   several nodes or users risks contention and a corrupted store, and"
            echo "   it doubles the project's usage. Point PODMANHPC_GRAPH_ROOT and"
            echo "   PODMANHPC_RUN_ROOT at \$SCRATCH, or unset both for the node-local"
            echo "   default, and keep only --squash-dir on CFS." ;;
    esac
fi

cat <<EOF
>> done. Use it from a job:

   export PODMANHPC_ADDITIONAL_STORES=$STORE_RO     # or: source env.sh
   srun ... podman-hpc run --rm --gpu \\
       -v \$SCRATCH:\$SCRATCH -v \$CFS:\$CFS --workdir "\$SLURM_SUBMIT_DIR" \\
       $REF python script.py

   Check it resolves before submitting:
       PODMANHPC_ADDITIONAL_STORES=$STORE_RO podman-hpc images | grep ${NAME}
EOF
