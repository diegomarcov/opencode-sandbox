#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-opencode-sandbox:dev}"
CONTAINER_NAME="${CONTAINER_NAME:-opencode-sandbox}"
STATE_VOLUME="${STATE_VOLUME-}"
HOST_WORKDIR="${HOST_WORKDIR:-$PWD}"
MEMORY_LIMIT="${MEMORY_LIMIT:-1g}"
CPU_LIMIT="${CPU_LIMIT:-1.0}"
PIDS_LIMIT="${PIDS_LIMIT:-256}"
NETWORK_MODE="${NETWORK_MODE:-bridge}"
READ_ONLY_ROOTFS="${READ_ONLY_ROOTFS:-true}"
TMPFS_SIZE="${TMPFS_SIZE:-128m}"
RUN_TMPFS_SIZE="${RUN_TMPFS_SIZE:-64m}"
HOST_OS="${HOST_OS:-$(uname -s)}"
CONTAINER_UID="${CONTAINER_UID:-}"
CONTAINER_GID="${CONTAINER_GID:-}"

if [[ -z "$CONTAINER_UID" ]]; then
  if [[ "$HOST_OS" == "Darwin" ]]; then
    CONTAINER_UID="10001"
  else
    CONTAINER_UID="$(id -u)"
  fi
fi

if [[ -z "$CONTAINER_GID" ]]; then
  if [[ "$HOST_OS" == "Darwin" ]]; then
    CONTAINER_GID="10001"
  else
    CONTAINER_GID="$(id -g)"
  fi
fi
RUN_USER_TMPFS_SIZE="${RUN_USER_TMPFS_SIZE:-32m}"
APPARMOR_PROFILE="${APPARMOR_PROFILE-}"
REQUIRE_APPARMOR="${REQUIRE_APPARMOR:-false}"
HOST_WORKDIR_MOUNT_OPTS="rw"

if [[ "$(uname -s)" == "Linux" ]]; then
  HOST_WORKDIR_MOUNT_OPTS="rw,z"
fi

if [[ ! "$CONTAINER_UID" =~ ^[0-9]+$ || "$CONTAINER_UID" -eq 0 ]]; then
  echo "Invalid CONTAINER_UID: ${CONTAINER_UID}" >&2
  exit 1
fi

if [[ ! "$CONTAINER_GID" =~ ^[0-9]+$ ]]; then
  echo "Invalid CONTAINER_GID: ${CONTAINER_GID}" >&2
  exit 1
fi

if [[ -z "$STATE_VOLUME" ]]; then
  if [[ "$CONTAINER_UID" == "10001" ]]; then
    STATE_VOLUME="opencode-home"
  else
    STATE_VOLUME="opencode-home-${CONTAINER_UID}"
  fi
fi

if [[ "$(uname -s)" == "Linux" ]]; then
  docker run --rm --user 0:0 \
    -v "$STATE_VOLUME:/home/opencode" \
    "$IMAGE_NAME" \
    /bin/bash -lc "install -d -m 700 /home/opencode && chown \"${CONTAINER_UID}:${CONTAINER_GID}\" /home/opencode"
fi

if [[ "$#" -eq 0 ]]; then
  run_command=(opencode)
elif [[ "$1" == -* ]]; then
  run_command=(opencode "$@")
else
  run_command=("$@")
fi

run_args=(
  --rm
  -i
  --name "$CONTAINER_NAME"
  --network "$NETWORK_MODE"
  --security-opt no-new-privileges:true
  --cap-drop=ALL
  --pids-limit "$PIDS_LIMIT"
  --memory "$MEMORY_LIMIT"
  --cpus "$CPU_LIMIT"
  --user "${CONTAINER_UID}:${CONTAINER_GID}"
)

case "${REQUIRE_APPARMOR,,}" in
  1|true|yes|on)
    enforce_apparmor=true
    ;;
  0|false|no|off|"")
    enforce_apparmor=false
    ;;
  *)
    echo "Invalid REQUIRE_APPARMOR value: ${REQUIRE_APPARMOR}" >&2
    echo "Use true|false (or yes|no, 1|0)" >&2
    exit 1
    ;;
esac

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
    if [[ "$enforce_apparmor" == true ]]; then
      echo "REQUIRE_APPARMOR=true requires AppArmor to be available on this host." >&2
      echo "Set APPARMOR_PROFILE to a valid profile name, or set REQUIRE_APPARMOR=false." >&2
      exit 1
    fi

    echo "Warning: APPARMOR_PROFILE is set but AppArmor is not available on this host; running without AppArmor." >&2
  fi
else
  if [[ "$enforce_apparmor" == true ]]; then
    echo "REQUIRE_APPARMOR=true requires APPARMOR_PROFILE to be set." >&2
    echo "Set APPARMOR_PROFILE to a valid profile name (for example, opencode-sandbox)." >&2
    exit 1
  fi
fi

case "${READ_ONLY_ROOTFS,,}" in
  1|true|yes|on)
    run_args+=(
      --read-only
      --tmpfs "/tmp:size=${TMPFS_SIZE},mode=1777,nodev,nosuid,exec"
      --tmpfs "/run:size=${RUN_TMPFS_SIZE},mode=1777,nodev,nosuid"
      --tmpfs "/run/user/${CONTAINER_UID}:size=${RUN_USER_TMPFS_SIZE},mode=700,nodev,nosuid,uid=${CONTAINER_UID},gid=${CONTAINER_GID}"
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
  -v "$HOST_WORKDIR:/work:${HOST_WORKDIR_MOUNT_OPTS}"
  -v "$STATE_VOLUME:/home/opencode"
  -w /work
)

docker run "${run_args[@]}" "$IMAGE_NAME" "${run_command[@]}"
