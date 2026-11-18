#!/bin/bash
# Build the idrobolab image on THIS host and push it to a registry (GHCR by
# default). Delta and Perlmutter both consume the same image. It also pushes the sources
# image (the Dockerfile's `sources` stage: the source code of the GPL software in the
# image), in this order: <image>:<date>-sources, then the image, then <image>:<tag>-sources.
# <date> is the UTC date and time the script started, a tag that stays when <tag> moves; the
# image records it in /opt/idrobolab/SOURCES.txt, so it names exactly its sources image, and
# no binary is out without its source. If the push of the image fails, <tag>-sources still
# matches the old <tag>.
# A sources image is never deleted while its image is available by tag or digest.
#
# Prerequisites:
#   1. ./prepare_build_context.sh first (stages ./src from /workspaces/code and
#      lammps-gpu-selftest.sh from core/lammps/).
#   2. docker or podman, and GHCR_USER (your GitHub username) and
#      GITHUB_PACKAGE_TOKEN (a PAT with write:packages) in the environment: the
#      script logs in to ghcr.io with them.
#
# Env overrides: IMAGE, TAG, ENGINE.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-ghcr.io/idrobolab/idrobolab}
TAG=${TAG:-latest}
SOURCES_TAG=$(date -u +%Y%m%d-%H%M%S)-sources
ENGINE=${ENGINE:-$(command -v podman || command -v docker || true)}
: "${ENGINE:?need podman or docker on PATH}"

if [ ! -d src ]; then
    echo "ERROR: build context not staged. Run ./prepare_build_context.sh first" >&2
    exit 1
fi

# The Dockerfile COPYs lammps-gpu-selftest.sh from this directory; it is staged from core/.
if ! cmp -s lammps-gpu-selftest.sh ../../../../core/lammps/lammps-gpu-selftest.sh; then
    echo "ERROR: lammps-gpu-selftest.sh is missing or differs from core/lammps/. Run ./prepare_build_context.sh again" >&2
    exit 1
fi

# An unauthenticated push to GHCR fails as "Requesting bearer token: 403
# Forbidden" (not 401), which reads like a permissions problem rather than a
# missing login. Check the credentials before the build and log in explicitly.
: "${GHCR_USER:?set GHCR_USER to your GitHub username}"
: "${GITHUB_PACKAGE_TOKEN:?set GITHUB_PACKAGE_TOKEN to a PAT with write:packages}"

echo ">> building ${IMAGE}:${TAG}  (engine: ${ENGINE##*/})"
"$ENGINE" build --build-arg SOURCES_TAG="$SOURCES_TAG" -t "${IMAGE}:${TAG}" .

echo ">> building ${IMAGE}:${TAG}-sources  (stage sources of the same build)"
"$ENGINE" build --target sources -t "${IMAGE}:${TAG}-sources" -t "${IMAGE}:${SOURCES_TAG}" .

echo ">> logging in to ghcr.io  (engine: ${ENGINE##*/})"
echo "$GITHUB_PACKAGE_TOKEN" | "$ENGINE" login ghcr.io -u "$GHCR_USER" --password-stdin

echo ">> pushing ${IMAGE}:${SOURCES_TAG}"
"$ENGINE" push "${IMAGE}:${SOURCES_TAG}"

echo ">> pushing ${IMAGE}:${TAG}"
"$ENGINE" push "${IMAGE}:${TAG}"

echo ">> pushing ${IMAGE}:${TAG}-sources"
"$ENGINE" push "${IMAGE}:${TAG}-sources"

cat <<EOF
>> done. Consume it:
   Delta:      apptainer build idrobolab.sif docker://${IMAGE}:${TAG}
   Perlmutter: podman-hpc pull ${IMAGE}:${TAG}
   nionswift GUI (needs a forwarded display, e.g. ThinLinc/X):
       apptainer exec --nv idrobolab.sif nionswift
     headless (no display): apptainer exec idrobolab.sif xvfb-run -a nionswift
EOF
