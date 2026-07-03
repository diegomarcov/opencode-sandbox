#!/usr/bin/env bash
set -euo pipefail

AVD_NAME="${AVD_NAME:-sandbox}"
EMULATOR_GPU="${EMULATOR_GPU:-swiftshader_indirect}"
EMULATOR_NO_WINDOW="${EMULATOR_NO_WINDOW:-true}"
EMULATOR_EXTRA_ARGS="${EMULATOR_EXTRA_ARGS:-}"

if ! avdmanager list avd | grep -q "Name: ${AVD_NAME}"; then
  echo "AVD ${AVD_NAME} not found. Run android-avd-init.sh first." >&2
  exit 1
fi

emulator_args=(-avd "${AVD_NAME}" -gpu "${EMULATOR_GPU}")

if [[ "$(echo "${EMULATOR_NO_WINDOW}" | tr '[:upper:]' '[:lower:]')" == "true" ]]; then
  emulator_args+=(-no-window)
fi

if [[ -e /dev/kvm ]]; then
  emulator_args+=(-accel on)
else
  echo "Warning: /dev/kvm not available; emulator will use software acceleration." >&2
  emulator_args+=(-accel off)
fi

if [[ -n "${EMULATOR_EXTRA_ARGS}" ]]; then
  # shellcheck disable=SC2206
  extra_args=(${EMULATOR_EXTRA_ARGS})
  emulator_args+=("${extra_args[@]}")
fi

exec emulator "${emulator_args[@]}"
