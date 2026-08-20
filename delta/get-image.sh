#!/bin/bash
# Materialize the Delta .sif from the shared image. Preferred path: convert the
# registry image built+pushed by shared/containers/x86_64-cuda/otherimage/publish.sh.
#
# Run on Delta (or any host with apptainer). Keep the .sif and cache off $HOME:
#   export APPTAINER_CACHEDIR=$SCRATCH/.apptainer
set -euo pipefail
IMAGE=${IMAGE:-ghcr.io/<username>/otherimage}
TAG=${TAG:-latest}
SIF=${SIF:-otherimage_delta.sif}

# From the registry (fastest; no local build):
apptainer build "$SIF" "docker://${IMAGE}:${TAG}"

echo ">> $SIF ready. sha256 for provenance:"; sha256sum "$SIF"
echo ">> run: apptainer exec --nv $SIF python script.py   (see jobs/ for Slurm)"

# Alternatives (uncomment as needed):
# --- local OCI build then convert (no registry): ------------------------------
#   (cd ../shared/containers/x86_64-cuda/otherimage && ./prepare_build_context.sh && podman build -t otherimage:latest .)
#   apptainer build "$SIF" docker-daemon://otherimage:latest
