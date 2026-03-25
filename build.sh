#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-air-gap}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
PLATFORM="${PLATFORM:-linux/amd64}"

echo "[build] Building ${IMAGE_NAME}:${IMAGE_TAG}"

docker build \
  --platform "$PLATFORM" \
  --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
  --file Dockerfile \
  .

echo "[build] Done: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Run with:"
echo "  docker run -it --rm \\"
echo "    -v ~/.ssh/id_rsa:/root/.ssh/id_rsa:ro \\"
echo "    -v \$(pwd)/group_vars/all.yml:/airgapped/group_vars/all.yml \\"
echo "    ${IMAGE_NAME}:${IMAGE_TAG}"
