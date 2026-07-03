#!/usr/bin/env bash
set -euo pipefail

AVD_NAME="${AVD_NAME:-sandbox}"
AVD_DEVICE="${AVD_DEVICE:-pixel_6}"

if [[ -z "${ANDROID_EMULATOR_IMAGE:-}" ]]; then
  case "$(uname -m)" in
    x86_64|amd64)
      ANDROID_EMULATOR_IMAGE="${ANDROID_EMULATOR_IMAGE_AMD64:-system-images;android-34;google_apis;x86_64}"
      ;;
    aarch64|arm64)
      ANDROID_EMULATOR_IMAGE="${ANDROID_EMULATOR_IMAGE_ARM64:-system-images;android-34;google_apis;arm64-v8a}"
      ;;
    *)
      echo "Unsupported architecture for AVD init: $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

if avdmanager list avd | grep -q "Name: ${AVD_NAME}"; then
  echo "AVD already exists: ${AVD_NAME}"
  exit 0
fi

echo "Creating AVD ${AVD_NAME} with image ${ANDROID_EMULATOR_IMAGE}"
echo no | avdmanager create avd \
  -n "${AVD_NAME}" \
  -k "${ANDROID_EMULATOR_IMAGE}" \
  --device "${AVD_DEVICE}"
