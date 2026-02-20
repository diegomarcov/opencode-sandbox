#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-opencode-sandbox:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-opencode-sandbox}"
STATE_VOLUME="${STATE_VOLUME:-opencode-home}"
HOST_WORKDIR="${HOST_WORKDIR:-$PWD}"
MEMORY_LIMIT="${MEMORY_LIMIT:-1g}"
CPU_LIMIT="${CPU_LIMIT:-1.0}"
PIDS_LIMIT="${PIDS_LIMIT:-256}"
READ_ONLY_ROOTFS="${READ_ONLY_ROOTFS:-true}"
TMPFS_SIZE="${TMPFS_SIZE:-128m}"
RUN_TMPFS_SIZE="${RUN_TMPFS_SIZE:-64m}"
CONTAINER_UID="${CONTAINER_UID:-10001}"
RUN_USER_TMPFS_SIZE="${RUN_USER_TMPFS_SIZE:-32m}"
APPARMOR_PROFILE="${APPARMOR_PROFILE-}"

run_args=(
  --rm
  -i
  --name "$CONTAINER_NAME"
  --security-opt no-new-privileges:true
  --cap-drop=ALL
  --pids-limit "$PIDS_LIMIT"
  --memory "$MEMORY_LIMIT"
  --cpus "$CPU_LIMIT"
)

if [[ -t 0 && -t 1 ]]; then
  run_args+=( -t )
fi

if [[ -n "$APPARMOR_PROFILE" ]]; then
  supports_apparmor=false
  if [[ "$(uname -s)" == "Linux" ]]; then
    security_options="$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null || true)"
    if [[ "$security_options" == *"apparmor"* ]]; then
      supports_apparmor=true
    fi
  fi

  if [[ "$supports_apparmor" == true ]]; then
    run_args+=(--security-opt "apparmor=${APPARMOR_PROFILE}")
  else
    echo "Warning: APPARMOR_PROFILE is set but AppArmor is not available on this host; running without AppArmor." >&2
  fi
fi

case "${READ_ONLY_ROOTFS,,}" in
  1|true|yes|on)
    run_args+=(
      --read-only
      --tmpfs "/tmp:size=${TMPFS_SIZE},mode=1777,nodev,nosuid,exec"
      --tmpfs "/run:size=${RUN_TMPFS_SIZE},mode=1777,nodev,nosuid"
      --tmpfs "/run/user/${CONTAINER_UID}:size=${RUN_USER_TMPFS_SIZE},mode=700,nodev,nosuid,uid=${CONTAINER_UID},gid=${CONTAINER_UID}"
      -e "XDG_RUNTIME_DIR=/run/user/${CONTAINER_UID}"
    )
    ;;
  0|false|no|off)
    :
    ;;
  *)
    echo "Unsupported READ_ONLY_ROOTFS value: ${READ_ONLY_ROOTFS}" >&2
    echo "Use true|false (or yes|no, 1|0)" >&2
    exit 1
    ;;
esac

run_args+=(
  -v "$HOST_WORKDIR:/work"
  -v "$STATE_VOLUME:/home/opencode"
  -w /work
)

docker run "${run_args[@]}" "$IMAGE_NAME" "$@"
