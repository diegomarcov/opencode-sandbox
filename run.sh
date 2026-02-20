#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-opencode-sandbox:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-opencode-sandbox}"
STATE_VOLUME="${STATE_VOLUME:-opencode-home}"
HOST_WORKDIR="${HOST_WORKDIR:-$PWD}"
MEMORY_LIMIT="${MEMORY_LIMIT:-1g}"
CPU_LIMIT="${CPU_LIMIT:-1.0}"
PIDS_LIMIT="${PIDS_LIMIT:-256}"

docker run --rm -it \
  --name "$CONTAINER_NAME" \
  --security-opt no-new-privileges:true \
  --cap-drop=ALL \
  --pids-limit "$PIDS_LIMIT" \
  --memory "$MEMORY_LIMIT" \
  --cpus "$CPU_LIMIT" \
  -v "$HOST_WORKDIR:/work" \
  -v "$STATE_VOLUME:/home/opencode" \
  -w /work \
  "$IMAGE_NAME" "$@"
