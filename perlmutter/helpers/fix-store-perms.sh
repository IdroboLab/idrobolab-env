#!/bin/bash
# Make a shared podman-hpc store readable by the whole project, and verify it.
#
# Why this is needed at all: `umask` is not sufficient. containers/storage sets
# explicit modes on some metadata -- the per-image directory and its `manifest`
# in particular -- so those land 0700 no matter what the caller's umask is, even
# while everything around them is 0775/0664. A collaborator then reads
# images.json, learns the image ID, and fails with
#
#   Error: locating item named "manifest" for image with ID <id>
#          (consider removing the image to resolve the issue): file does not exist
#
# which reads as a corrupt store but is a permission problem. podman reacts by
# re-downloading the image. Do NOT follow the "consider removing the image"
# advice: that deletes a good 14 GB image to work around a chmod.
#
# Nor can this be made to stick with a default ACL. A POSIX default ACL masks
# the mode a process REQUESTS at creation; it cannot grant more than was asked
# for, so a process that explicitly creates 0700 still gets 0700. The only
# reliable fix is to re-apply the permissions after whatever wrote the store --
# which is why update-image.sh calls this on every pull.
#
# Usage:
#   ./fix-store-perms.sh                  # fix $PODMAN_STORE (or the default)
#   ./fix-store-perms.sh /path/to/store   # fix a specific store
#   ./fix-store-perms.sh --check [path]   # report only; exit 1 if anything is
#                                         # not group-readable. Safe to cron.
set -euo pipefail

CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi

STORE=${1:-${PODMAN_STORE:-/global/cfs/cdirs/<project>/podman-hpc/images}}

case "$STORE" in
    /dvs_ro/*)
        echo "ERROR: $STORE is the read-only DVS mirror; pass the /global/cfs path" >&2
        exit 1 ;;
esac
[ -d "$STORE" ] || { echo "ERROR: no such store: $STORE" >&2; exit 1; }

offender() { find "$STORE" ! -perm -g+r -print -quit 2>/dev/null || true; }

if [ "$CHECK" = 1 ]; then
    bad=$(offender)
    if [ -n "$bad" ]; then
        echo "NOT group-readable: $bad" >&2
        echo "  collaborators will hit \"manifest ... file does not exist\" and re-pull" >&2
        echo "  fix with: $0 $STORE" >&2
        exit 1
    fi
    echo "OK: $STORE is fully group-readable"
    exit 0
fi

[ -w "$STORE" ] || { echo "ERROR: $STORE is not writable by ${USER:-$(id -un)}" >&2; exit 1; }

# g+rX -- capital X adds execute to directories and to files that already have
# it, never to plain data files. setgid on directories so anything written later
# inherits the project group rather than the writer's default group.
chmod -R g+rX "$STORE"
find "$STORE" -type d -exec chmod g+s {} + 2>/dev/null || true

bad=$(offender)
if [ -n "$bad" ]; then
    echo "WARNING: still not group-readable after the fix: $bad" >&2
    echo "         Are you the owner? ls -l on that path will say." >&2
    exit 1
fi
echo ">> $STORE is fully group-readable (verified)"
