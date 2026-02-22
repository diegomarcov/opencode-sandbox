#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE_NAME_OVERRIDE="${IMAGE_NAME-}"
IMAGE_NAME="${IMAGE_NAME:-opencode-sandbox:dev}"
SANDBOX_ENV="${SANDBOX_ENV:-opencode}"
CONTAINER_NAME="${CONTAINER_NAME:-opencode-sandbox}"
STATE_VOLUME="${STATE_VOLUME-}"
STATE_INIT_MODE="${STATE_INIT_MODE:-auto}"
STATE_BIND_DIR="${STATE_BIND_DIR:-${HOME}/.local/share/opencode-sandbox/state}"
HOST_WORKDIR="${HOST_WORKDIR:-$PWD}"
MEMORY_LIMIT="${MEMORY_LIMIT:-1g}"
CPU_LIMIT="${CPU_LIMIT:-1.0}"
PIDS_LIMIT="${PIDS_LIMIT:-256}"
NETWORK_MODE="${NETWORK_MODE:-bridge}"
READ_ONLY_ROOTFS="${READ_ONLY_ROOTFS:-true}"
TMPFS_SIZE="${TMPFS_SIZE:-128m}"
RUN_TMPFS_SIZE="${RUN_TMPFS_SIZE:-64m}"
RUN_USER_TMPFS_SIZE="${RUN_USER_TMPFS_SIZE:-32m}"
HOST_OS_INPUT="${HOST_OS:-$(uname -s)}"
CONTAINER_UID="${CONTAINER_UID:-}"
CONTAINER_GID="${CONTAINER_GID:-}"
SECCOMP_PROFILE="${SECCOMP_PROFILE-}"
SECCOMP_ENFORCE="${SECCOMP_ENFORCE-}"
APPARMOR_PROFILE="${APPARMOR_PROFILE-}"
REQUIRE_APPARMOR="${REQUIRE_APPARMOR:-false}"
HOST_WORKDIR_MOUNT_OPTS="rw"

SCRIPT_ARGS=()

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_sandbox_env() {
  case "$(to_lower "$1")" in
    opencode|python)
      return 0
      ;;
    *)
      echo "Unsupported SANDBOX_ENV: $1" >&2
      echo "Supported values: opencode, python" >&2
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sandbox-env=*)
      SANDBOX_ENV="${1#--sandbox-env=}"
      if [[ -z "$SANDBOX_ENV" ]]; then
        echo "--sandbox-env requires an environment value" >&2
        exit 1
      fi
      shift
      ;;
    --sandbox-env)
      if [[ $# -lt 2 ]]; then
        echo "--sandbox-env requires an environment value" >&2
        exit 1
      fi
      SANDBOX_ENV="$2"
      shift 2
      ;;
    --workdir)
      if [[ $# -lt 2 ]]; then
        echo "--workdir requires a directory argument" >&2
        exit 1
      fi
      HOST_WORKDIR="$2"
      shift 2
      ;;
    --workdir=*)
      HOST_WORKDIR="${1#--workdir=}"
      shift
      ;;
    *)
      SCRIPT_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${HOST_WORKDIR}" ]]; then
  echo "HOST_WORKDIR is empty" >&2
  exit 1
fi

if ! validate_sandbox_env "$SANDBOX_ENV"; then
  exit 1
fi

SANDBOX_ENV="$(to_lower "$SANDBOX_ENV")"

if [[ -z "${IMAGE_NAME_OVERRIDE}" ]]; then
  case "$(to_lower "$SANDBOX_ENV")" in
    opencode)
      IMAGE_NAME="${IMAGE_NAME_OPENCODE:-opencode-sandbox:dev}"
      ;;
    python)
      IMAGE_NAME="${IMAGE_NAME_PYTHON:-opencode-sandbox-python:dev}"
      ;;
  esac
fi

is_true() {
  case "$(to_lower "$1")" in
    1|true|yes|on)
      return 0
      ;;
    0|false|no|off|"")
      return 1
      ;;
    *)
      return 2
      ;;
  esac
}

case "$(to_lower "$HOST_OS_INPUT")" in
  linux*)
    HOST_OS="Linux"
    ;;
  darwin*)
    HOST_OS="Darwin"
    ;;
  *)
    echo "Unsupported HOST_OS: ${HOST_OS_INPUT}" >&2
    echo "Supported values: Linux, Darwin" >&2
    exit 1
    ;;
esac

case "$(to_lower "$STATE_INIT_MODE")" in
  auto|volume|bind)
    :
    ;;
  *)
    echo "Invalid STATE_INIT_MODE: ${STATE_INIT_MODE}" >&2
    echo "Use auto, volume, or bind" >&2
    exit 1
    ;;
esac

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

if [[ -z "$SECCOMP_ENFORCE" ]]; then
  if [[ "$HOST_OS" == "Darwin" ]]; then
    SECCOMP_ENFORCE=true
  else
    SECCOMP_ENFORCE=false
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found in PATH." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not accessible. Is Docker running and is your user allowed to use it?" >&2
  echo "If needed, run: sudo usermod -aG docker \$USER and re-login." >&2
  exit 1
fi

if [[ "$HOST_OS" == "Linux" ]]; then
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

state_mount_source="$STATE_VOLUME"
state_mount_description="named volume"

state_mount_is_writable() {
  local mount_source="$1"

  docker run --rm \
    --user "${CONTAINER_UID}:${CONTAINER_GID}" \
    -v "${mount_source}:/home/opencode" \
    "$IMAGE_NAME" \
    /bin/bash -lc 'test -w /home/opencode' >/dev/null 2>&1
}

case "$(to_lower "$STATE_INIT_MODE")" in
  volume)
    if ! state_mount_is_writable "$STATE_VOLUME"; then
      echo "STATE_INIT_MODE=volume is set, but ${STATE_VOLUME} is not writable by UID:GID ${CONTAINER_UID}:${CONTAINER_GID}." >&2
      echo "Tip: set STATE_INIT_MODE=auto (default) and keep STATE_BIND_DIR writable, or use matching CONTAINER_UID/CONTAINER_GID values." >&2
      exit 1
    fi
    ;;
  bind)
    if ! mkdir -p "$STATE_BIND_DIR"; then
      echo "Failed to create STATE_BIND_DIR: ${STATE_BIND_DIR}" >&2
      exit 1
    fi
    chmod 700 "$STATE_BIND_DIR"
    if ! state_mount_is_writable "$STATE_BIND_DIR"; then
      echo "STATE_BIND_DIR is not writable by UID:GID ${CONTAINER_UID}:${CONTAINER_GID}: ${STATE_BIND_DIR}" >&2
      echo "Choose a writable host directory or adjust CONTAINER_UID/CONTAINER_GID." >&2
      exit 1
    fi
    state_mount_source="$STATE_BIND_DIR"
    state_mount_description="bind directory"
    ;;
  auto)
    if state_mount_is_writable "$STATE_VOLUME"; then
      :
    else
      echo "Named state volume ${STATE_VOLUME} is not writable by UID:GID ${CONTAINER_UID}:${CONTAINER_GID}."
      echo "Falling back to bind directory: ${STATE_BIND_DIR}."
      if ! mkdir -p "$STATE_BIND_DIR"; then
        echo "Failed to create STATE_BIND_DIR: ${STATE_BIND_DIR}" >&2
        exit 1
      fi
      chmod 700 "$STATE_BIND_DIR"
      if ! state_mount_is_writable "$STATE_BIND_DIR"; then
        echo "STATE_BIND_DIR is not writable by UID:GID ${CONTAINER_UID}:${CONTAINER_GID}: ${STATE_BIND_DIR}" >&2
        echo "Use a writable STATE_BIND_DIR and STATE_INIT_MODE=bind, or set a matching CONTAINER_UID/CONTAINER_GID for volume mode." >&2
        exit 1
      fi
      state_mount_source="$STATE_BIND_DIR"
      state_mount_description="bind directory (fallback)"
    fi
    ;;
esac

if [[ "${#SCRIPT_ARGS[@]}" -eq 0 ]]; then
  run_command=(opencode)
elif [[ "${SCRIPT_ARGS[0]}" == -* ]]; then
  run_command=(opencode "${SCRIPT_ARGS[@]}")
else
  run_command=("${SCRIPT_ARGS[@]}")
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

case "$(to_lower "$REQUIRE_APPARMOR")" in
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

proxy_env_vars=(
  HTTP_PROXY
  HTTPS_PROXY
  ALL_PROXY
  NO_PROXY
  http_proxy
  https_proxy
  all_proxy
  no_proxy
)

for env_var in "${proxy_env_vars[@]}"; do
  if [[ -n "${!env_var-}" ]]; then
    run_args+=( -e "${env_var}=${!env_var}" )
  fi
done

if [[ -n "$APPARMOR_PROFILE" ]]; then
  supports_apparmor=false
  if [[ "$HOST_OS" == "Linux" ]]; then
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

if [[ -z "$SECCOMP_PROFILE" && "$HOST_OS" == "Darwin" ]]; then
  SECCOMP_PROFILE="${SCRIPT_DIR}/seccomp/opencode-mac.json"
fi

if [[ -n "$SECCOMP_PROFILE" ]]; then
  if [[ "$SECCOMP_PROFILE" != /* ]]; then
    SECCOMP_PROFILE="${SCRIPT_DIR}/${SECCOMP_PROFILE}"
  fi

  if [[ ! -f "$SECCOMP_PROFILE" ]]; then
    if is_true "$SECCOMP_ENFORCE"; then
      echo "SECCOMP_ENFORCE is true but seccomp profile is missing: ${SECCOMP_PROFILE}" >&2
      exit 1
    fi
    echo "Warning: seccomp profile not found (${SECCOMP_PROFILE}); running without seccomp." >&2
    SECCOMP_PROFILE=""
  fi

  if [[ -n "$SECCOMP_PROFILE" ]]; then
    run_args+=(--security-opt "seccomp=${SECCOMP_PROFILE}")
  fi
fi

case "$(to_lower "$READ_ONLY_ROOTFS")" in
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
  -v "${state_mount_source}:/home/opencode"
  -w /work
)

echo "State mount mode: ${state_mount_description} -> ${state_mount_source}"
docker run "${run_args[@]}" "$IMAGE_NAME" "${run_command[@]}"
