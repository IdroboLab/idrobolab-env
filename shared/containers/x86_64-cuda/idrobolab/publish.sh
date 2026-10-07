#!/bin/bash
# Build the idrobolab image on THIS host and push it to a registry (GHCR by
# default). Delta and Perlmutter both consume the same image.
#
# Prerequisites:
#   1. ./prepare_build_context.sh first (stages ./src from /workspaces/code).
#   2. docker or podman, and GHCR_USER (your GitHub username) and
#      GITHUB_PACKAGE_TOKEN (a PAT with write:packages) in the environment: the
#      script logs in to ghcr.io with them.
#
# Env overrides: IMAGE, TAG, ENGINE.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-ghcr.io/idrobolab/idrobolab}
TAG=${TAG:-latest}
ENGINE=${ENGINE:-$(command -v podman || command -v docker || true)}
: "${ENGINE:?need podman or docker on PATH}"

if [ ! -d src ]; then
    echo "ERROR: build context not staged. Run ./prepare_build_context.sh first" >&2
    exit 1
fi

echo ">> building ${IMAGE}:${TAG}  (engine: ${ENGINE##*/})"
"$ENGINE" build -t "${IMAGE}:${TAG}" .

# An unauthenticated push to GHCR fails as "Requesting bearer token: 403
# Forbidden" (not 401), which reads like a permissions problem rather than a
# missing login. Log in explicitly.
: "${GHCR_USER:?set GHCR_USER to your GitHub username}"
: "${GITHUB_PACKAGE_TOKEN:?set GITHUB_PACKAGE_TOKEN to a PAT with write:packages}"
echo ">> logging in to ghcr.io  (engine: ${ENGINE##*/})"
echo "$GITHUB_PACKAGE_TOKEN" | "$ENGINE" login ghcr.io -u "$GHCR_USER" --password-stdin

echo ">> pushing ${IMAGE}:${TAG}"
"$ENGINE" push "${IMAGE}:${TAG}"

cat <<EOF
>> done. Consume it:
   Delta:      apptainer build idrobolab.sif docker://${IMAGE}:${TAG}
   Perlmutter: podman-hpc pull ${IMAGE}:${TAG}
   nionswift GUI (needs a forwarded display, e.g. ThinLinc/X):
       apptainer exec --nv idrobolab.sif nionswift
     headless (no display): apptainer exec idrobolab.sif xvfb-run -a nionswift
EOF
