#!/bin/bash
# Pull (or refresh) a container image into a podman-hpc squash store. A released tag goes
# to the project's shared store on CFS, which survives $SCRATCH purges and is readable by
# the whole project. A dev build or release candidate (TAG=dev, TAG=<N>-rc) goes to the
# puller's own store, podman-hpc's default squash directory $SCRATCH/storage: those tags
# exist for testing and verification, and stay out of the group's store.
#
# Run on a Perlmutter LOGIN node — compute nodes have no route to ghcr.io.
#
# Usage:
#   ./update-image.sh                      # ghcr.io/idrobolab/idrobolab:latest
#   TAG=v2 ./update-image.sh idrobolab     # a specific tag
#   TAG=dev ./update-image.sh idrobolab    # a dev build, into $SCRATCH/storage
#   IMAGE=ghcr.io/someone/thing ./update-image.sh   # any other image: repository, no tag (TAG sets it)
#   REFRESH=1 ./update-image.sh            # drop the squashed copy first
#
# Afterwards, jobs read the store through the DVS read-only mirror — see
# env.sh, which exports PODMANHPC_ADDITIONAL_STORES for exactly that.
set -euo pipefail

TAG=${TAG:-latest}

# Defaults match env.sh; sourcing that file first parameterises this script
# (PODMAN_STORE / PODMAN_STORE_RO), and STORE / STORE_RO still win if set.
# podman-hpc reads its default squash directory in every job without configuration.
OWN_STORE=${SCRATCH:+$SCRATCH/storage}
if [ -z "${STORE:-}" ]; then
    case $TAG in
        dev|*-rc) STORE=${OWN_STORE:?SCRATCH is not set; pass STORE=} ;;
        *)        STORE=${PODMAN_STORE:?set NERSC_PROJECT and source env.sh, or pass STORE=} ;;
    esac
fi
own_store=0
[ "$STORE" != "$OWN_STORE" ] || own_store=1

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
IMAGE=${IMAGE:-ghcr.io/${IMAGE_OWNER:-idrobolab}/$NAME}
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

# This store is advertised as readable by the whole project, and nothing else
# makes that true: mkdir and every file podman writes inherit the caller's
# umask, which is 022 at NERSC, so a collaborator gets ACCES on files they are
# supposed to share. Set a group-friendly umask for the whole run and setgid
# the directory so new entries inherit the project group.
umask "${IDROBOLAB_ENV_UMASK:-0002}"
mkdir -p "$STORE"
[ -w "$STORE" ] || { echo "ERROR: $STORE is not writable by $WHOAMI" >&2; exit 1; }
[ "$own_store" = 1 ] || chmod g+rxs "$STORE" 2>/dev/null || true

# The squash step writes into the shared store over several minutes and is not
# atomic, and podman-hpc itself takes no lock (its migrate step only creates
# empty .lock placeholders that nothing acquires). Two concurrent runs can
# therefore interleave and corrupt the store, so serialise here.
#
# Caveat worth knowing: flock semantics on a parallel filesystem are weaker
# than on a local one. This is a guard against the ordinary accident of two
# people pulling at once, not a hard guarantee.
if command -v flock >/dev/null 2>&1; then
    exec 9>"$STORE/.update-image.lock" || true
    if ! flock -w "${LOCK_WAIT:-1800}" 9; then
        echo "ERROR: another update-image.sh holds the store lock" >&2
        echo "       ($(cat "$STORE/.update-image.holder" 2>/dev/null || echo 'holder unknown'))." >&2
        echo "       Wait for it, or raise LOCK_WAIT (currently ${LOCK_WAIT:-1800}s)." >&2
        exit 1
    fi
    printf '%s on %s since %s\n' "$WHOAMI" "${HOSTNAME:-unknown}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STORE/.update-image.holder" 2>/dev/null || true
    trap 'rm -f "$STORE/.update-image.holder" 2>/dev/null || true' EXIT
else
    echo ">> note: flock unavailable — not serialising against concurrent pulls"
fi

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
            # GHCR's token endpoint answers 200 + {"token":...} when the repo
            # is anonymously readable, and 403 + {"errors":[{"code":"DENIED"}]}
            # when it is private OR does not exist — it deliberately does not
            # distinguish those two, so the message below must not either. An
            # unauthenticated
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

# --- clear truncated squash stubs ------------------------------------------
# podman-hpc's migrate skips whenever the target .squash already exists
# (migrate2scratch.py: `tgt = ...; if os.path.exists(tgt): return True`), and
# mksquashfs writes straight to that final path with no temp file and no rename.
# A squash that dies part-way therefore leaves a stub which turns every later
# migrate into a SILENT no-op -- the skip is logged at INFO, and podman-hpc
# never configures Python logging (its --log-level is forwarded only to the
# podman binary), so nothing prints and the exit status is 0. Observed in the
# wild: a 106-byte stub that survived a re-pull and three migrates.
#
# Only stubs that are BOTH implausibly small AND untouched for a while are
# removed, so a squash genuinely in progress in someone else's shell is safe.
# We also hold the store lock here.
if [ -d "$STORE/overlay/l" ]; then
    stubs=()
    while IFS= read -r line; do
        [ -n "$line" ] && stubs+=("$line")
    done < <(find "$STORE/overlay/l" -maxdepth 1 -name '*.squash' \
                  -size -1048576c -mmin "+${STUB_MAX_AGE_MIN:-30}" 2>/dev/null || true)
    # STUB_MAX_AGE_MIN=0 clears a stub you just created yourself -- the default
    # 30 exists only to protect a squash in progress in someone else's shell.
    # NB: -size in BYTES (c). GNU find rounds -size -1M up to whole 1 MiB
    # units, so a 106-byte stub counts as 1 and never matches -1M.
    if [ "${#stubs[@]}" -gt 0 ]; then
        echo ">> removing truncated squash stub(s) that would silently block migrate:"
        for f in "${stubs[@]}"; do
            echo "   $(du -h "$f" 2>/dev/null | cut -f1)  $f"
        done
        rm -f -- "${stubs[@]}"
    fi
fi

# --- pull -----------------------------------------------------------------
if [ "${REFRESH:-0}" = "1" ]; then
    # `podman-hpc rmi` is a passthrough to plain `podman rmi`: it removes the
    # GRAPH-ROOT copy only. podman-hpc does not even pass --squash-dir to it,
    # so the squashed copy in the shared store survives untouched. `rmsqi` is
    # the one that drops the squashed image. Do both, and report failures
    # rather than swallowing them — a REFRESH that silently no-ops is worse
    # than one that errors.
    echo ">> REFRESH: dropping the squashed copy of $REF from $STORE"
    podman-hpc --squash-dir "$STORE" rmsqi "$REF" \
        || echo "   note: rmsqi found nothing to remove (or failed)"
    echo ">> REFRESH: dropping the local graph-root copy of $REF"
    podman-hpc rmi "$REF" \
        || echo "   note: rmi found nothing to remove (or failed)"
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
# A non-integer here would make `[ "$n" -ge "$attempts" ]` exit 2 on the parse
# error; `if` reads that as false, `set -e` is suppressed inside a condition,
# and the give-up branch becomes unreachable — an unbounded retry loop on a
# login node. RETRIES=no/false/off are the natural ways someone tries to turn
# retrying OFF, and each would invert into "retry forever". Validate instead.
case $attempts in
    ''|*[!0-9]*)
        echo "ERROR: RETRIES must be a non-negative integer (got: '$attempts')." >&2
        echo "       To attempt the pull exactly once, use RETRIES=1." >&2
        exit 1 ;;
esac
[ "$attempts" -ge 1 ] || attempts=1
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

# --- shared-store permissions ----------------------------------------------
# Delegated to the sibling script so there is ONE copy of this logic; keeping a
# second inline copy is how the store paths drifted earlier in this repo. See
# fix-store-perms.sh for why umask is not sufficient and why a default ACL
# cannot replace re-applying the modes after each write.
# The own store is the puller's alone: nothing to share.
if [ "${FIX_PERMS:-1}" = "1" ] && [ "$own_store" = 0 ]; then
    _permfix="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fix-store-perms.sh"
    if [ -x "$_permfix" ]; then
        "$_permfix" "$STORE" || echo "WARNING: could not make $STORE group-readable" >&2
    else
        echo "WARNING: $_permfix missing -- store permissions NOT checked." >&2
        echo "         Collaborators may hit \"manifest ... file does not exist\"." >&2
    fi
fi

# --- provenance -----------------------------------------------------------
# The digest is what identifies the image in a campaign record; :latest moves.
echo ">> digest:"
podman-hpc --squash-dir "$STORE" images --digests | grep -E "REPOSITORY|${IMAGE}" || true

digest=$(podman-hpc --squash-dir "$STORE" inspect --format '{{index .RepoDigests 0}}' \
             "$REF" 2>/dev/null || echo "unknown")
# One log file per user rather than one shared file. A single file is created
# with the first puller's ownership and 0644, so every later collaborator's
# append fails with EACCES; per-user files also remove the interleave race
# between concurrent appends.
#
# The redirection is grouped deliberately: bash applies a simple command's
# redirections left to right, so a trailing 2>/dev/null is not yet in effect
# when the >> open fails and the shell's "Permission denied" still reaches
# the terminal. Wrapping in { } makes the suppression cover the open.
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
histdir="$STORE/pull-history.d"
histfile="$histdir/${WHOAMI}.log"
if { mkdir -p "$histdir" && printf '%s\t%s\t%s\t%s\n' \
        "$stamp" "$WHOAMI" "$REF" "$digest" >> "$histfile"; } 2>/dev/null; then
    echo ">> logged to $histfile"
else
    echo ">> note: could not write $histfile (check group permissions on $STORE)"
fi

# --- footprint ------------------------------------------------------------
# podman keeps TWO copies: the graph-root one it pulled into, and the squashed
# one it migrated to. Only the squashed copy is needed to run a job — that is
# how a collaborator who never pulled can use the store — so a graph root on a
# shared filesystem doubles usage and slows every pull for no benefit.
# Resolved unconditionally: the verification block below uses it to diagnose a
# failed squash, and that must work with FOOTPRINT=0 too.
graph_root=$(podman-hpc info --format '{{.Store.GraphRoot}}' 2>/dev/null) || graph_root=""

if [ "${FOOTPRINT:-1}" = "1" ]; then
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

# --- verify the shared store, not this node's view -------------------------
# `podman-hpc images` here also sees the graph-root copy that `podman pull`
# just wrote, so it answers "present" even when the migrate step produced
# nothing usable — the check this script used to merely PRINT could not fail.
# Point podman at a throwaway graph root so only the shared squash store can
# satisfy the lookup, which is what a compute node actually gets.
#
# Prefer the /dvs_ro mirror, but fall back to the writable path: login nodes do
# not always have the DVS mount.
probe_store=$STORE
[ -d "$STORE_RO" ] && probe_store=$STORE_RO
if probe_root=$(mktemp -d 2>/dev/null); then
    # Captured, then matched with a here-string: under pipefail a pipe into
    # grep -q fails whenever podman-hpc takes SIGPIPE after the first match.
    probe_list=$(PODMANHPC_GRAPH_ROOT="$probe_root/storage" \
                 PODMANHPC_RUN_ROOT="$probe_root/run" \
                 PODMANHPC_ADDITIONAL_STORES="$probe_store" \
                 podman-hpc images 2>/dev/null || true)
    if grep -qF "$IMAGE" <<<"$probe_list"; then
        echo ">> verified: $REF resolves from $probe_store with an empty graph root"
    else
        rm -rf "$probe_root"
        echo "ERROR: $REF is NOT visible through $probe_store with an empty graph" >&2
        echo "       root. The pull succeeded but the squash/migrate step did not," >&2
        echo "       so JOBS WILL NOT FIND THIS IMAGE. Note podman-hpc exits 0 even" >&2
        echo "       when its migrate fails ('ERROR:root:Squash Failed' in the log)," >&2
        echo "       which is why this check exists." >&2
        echo >&2
        echo "       Re-squash without re-downloading 20 GB. rmsqi FIRST: a" >&2
        echo "       part-written .squash blocks migrate silently, so migrate on" >&2
        echo "       its own returns 0 instantly and does nothing." >&2
        echo "         podman-hpc --squash-dir $STORE rmsqi $REF" >&2
        echo "         podman-hpc --squash-dir $STORE migrate $REF" >&2
        echo >&2
        if [ -n "$graph_root" ]; then
            case "$graph_root" in
                /pscratch/*|/global/cfs/*|/dvs_ro/*|/global/homes/*)
                    echo "       LIKELY CAUSE: the graph root is on a network filesystem" >&2
                    echo "         $graph_root" >&2
                    echo "       mksquashfs reads the layers through fuse-overlayfs there and" >&2
                    echo "       can fail on extended attributes ('Unrecognised xattr prefix')." >&2
                    echo "       podman warns about it too ('Network file system detected as" >&2
                    echo "       backing store'). Unset PODMANHPC_GRAPH_ROOT and" >&2
                    echo "       PODMANHPC_RUN_ROOT for the node-local default, then re-pull:" >&2
                    echo "         env -u PODMANHPC_GRAPH_ROOT -u PODMANHPC_RUN_ROOT \\" >&2
                    echo "             ./update-image.sh ${NAME}" >&2 ;;
            esac
        fi
        echo "       Also check the project CFS quota; a full quota fails the same way." >&2
        exit 1
    fi
    rm -rf "$probe_root"
fi

# --- one image per tag ------------------------------------------------------
# podman-hpc keeps tags per store, and a job reads both stores: a copy left in the other
# one under the same tag makes the tag name two images, and podman may run either.
# `images` lists an image once per store that holds it; `sort -u` folds those lines.
digests=$(podman-hpc images --digests --format '{{.Digest}}' "$REF" 2>/dev/null | sort -u) \
    || digests=""
if [ "$(printf '%s\n' "$digests" | grep -c .)" -gt 1 ]; then
    echo "ERROR: $REF now names several images:" $digests >&2
    echo "       This pull went to $STORE. Remove the copy from the store that holds it" >&2
    echo "       (rmsqi by tag; never in $STORE, which would remove the new image):" >&2
    for other in "$OWN_STORE" "${PODMAN_STORE:-}"; do
        [ -z "$other" ] || [ "$other" = "$STORE" ] ||
            echo "         podman-hpc --squash-dir $other rmsqi $REF" >&2
    done
    exit 1
fi

store_line="export PODMANHPC_ADDITIONAL_STORES=$STORE_RO     # or: source env.sh"
[ "$own_store" = 0 ] || store_line="# $STORE is podman-hpc's default: jobs read it as is"
cat <<EOF
>> done. Use it from a job:

   $store_line
   srun ... -L scratch,cfs podman-hpc run --rm --gpu \\
       -v \$SCRATCH:\$SCRATCH -v \$CFS:\$CFS -v \$HOME:\$HOME \\
       --workdir "\$PWD" \\
       $REF python script.py

   \$HOME is mounted because podman-hpc bind-mounts nothing by default and
   --workdir is often under it; see perlmutter/jobs/*.sbatch for the full
   pattern -- including the add_mount helper, which you need if you work from
   /global/cfs/projectdirs/<project> (the symlink spelling of \$CFS: it is not
   mounted by the one-liner above, and podman rejects a --workdir it cannot
   see).

   Re-check from a compute node (this node's graph-root copy would mask a
   broken store):
       srun -A "\$NERSC_PROJECT" -C gpu -q debug -N1 -t5 -L cfs \\
           podman-hpc run --rm $REF python -P -c "print('ok')"
EOF
