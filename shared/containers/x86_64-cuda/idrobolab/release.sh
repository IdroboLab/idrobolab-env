#!/bin/bash
# Release the tested release candidate: tag <IMAGE>:<N>-rc as <IMAGE>:<N> and <IMAGE>:latest, where
# N is VERSION. The only way :<N> and :latest move.
#
# It refuses unless
#   - every record in verification/idrobolab/releases/<N>/*.json carries the build id
#     (`build_id`) that the idrobolab.build-id label of <IMAGE>:<N>-rc has in the registry,
#     so the suite passed on this very image and not on an earlier build of the candidate;
#   - <IMAGE>:<N> does not exist yet (:<N> never moves).
# It then pushes both tags and checks that <N>-rc, <N> and latest resolve to one digest.
#
# Needs GHCR_USER (your GitHub username) and GITHUB_PACKAGE_TOKEN (a PAT with write:packages)
# in the environment; the token goes to the engine's stdin, and nothing here prints it.
#
# Env overrides: IMAGE, ENGINE.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-ghcr.io/idrobolab/idrobolab}
ENGINE=${ENGINE:-$(command -v podman || command -v docker || true)}
: "${ENGINE:?need podman or docker on PATH}"
: "${GHCR_USER:?set GHCR_USER to your GitHub username}"
: "${GITHUB_PACKAGE_TOKEN:?set GITHUB_PACKAGE_TOKEN to a PAT with write:packages}"

N=$(cat VERSION)
if ! [[ $N =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: VERSION is '${N}': there is nothing to release" >&2
    exit 1
fi

shopt -s nullglob
records=(../../../../verification/idrobolab/releases/"${N}"/*.json)
if [ ${#records[@]} -eq 0 ]; then
    echo "ERROR: no records in verification/idrobolab/releases/${N}/" >&2
    exit 1
fi

echo ">> logging in to ghcr.io  (engine: ${ENGINE##*/})"
echo "$GITHUB_PACKAGE_TOKEN" | "$ENGINE" login ghcr.io -u "$GHCR_USER" --password-stdin

# Registry digest of a tag, from a fresh pull (the engines list it in .RepoDigests).
digest() {
    "$ENGINE" pull -q "${IMAGE}:$1" >/dev/null
    "$ENGINE" image inspect --format '{{index .RepoDigests 0}}' "${IMAGE}:$1"
}

"$ENGINE" pull -q "${IMAGE}:${N}-rc" >/dev/null
rc_build_id=$("$ENGINE" image inspect --format '{{index .Config.Labels "idrobolab.build-id"}}' "${IMAGE}:${N}-rc")
if [ -z "$rc_build_id" ]; then
    echo "ERROR: ${IMAGE}:${N}-rc has no idrobolab.build-id label" >&2
    exit 1
fi
for record in "${records[@]}"; do
    # The records' format is defined by verification/ (a top-level build_id).
    record_build_id=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["build_id"])' "$record")
    if [ "$record_build_id" != "$rc_build_id" ]; then
        echo "ERROR: ${record##*/} has build id ${record_build_id}, ${IMAGE}:${N}-rc has ${rc_build_id}" >&2
        exit 1
    fi
done

# Only "manifest unknown" (podman, registries) or "no such manifest" (docker) means that :N is
# free; any other failure leaves it undecided.
if out=$("$ENGINE" manifest inspect "${IMAGE}:${N}" 2>&1); then
    echo "ERROR: ${IMAGE}:${N} exists already; :${N} never moves" >&2
    exit 1
elif ! grep -qiE 'manifest unknown|no such manifest' <<<"$out"; then
    echo "ERROR: cannot tell whether ${IMAGE}:${N} exists: ${out}" >&2
    exit 1
fi

"$ENGINE" tag "${IMAGE}:${N}-rc" "${IMAGE}:${N}"
"$ENGINE" tag "${IMAGE}:${N}-rc" "${IMAGE}:latest"
echo ">> pushing ${IMAGE}:${N}"
"$ENGINE" push "${IMAGE}:${N}"
echo ">> pushing ${IMAGE}:latest"
"$ENGINE" push "${IMAGE}:latest"

rc_digest=$(digest "${N}-rc")
for tag in "$N" latest; do
    if [ "$(digest "$tag")" != "$rc_digest" ]; then
        echo "ERROR: ${IMAGE}:${tag} does not resolve to ${rc_digest}" >&2
        exit 1
    fi
done
echo ">> released ${IMAGE}:${N} and :latest = ${rc_digest}"
