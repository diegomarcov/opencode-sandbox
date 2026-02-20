#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${BUILD_ENV_FILE:-${SCRIPT_DIR}/build.env}"

image_name_override="${IMAGE_NAME-}"
dockerfile_override="${DOCKERFILE-}"
version_override="${OPENCODE_VERSION-}"
platform_override="${OPENCODE_TARGETPLATFORM-}"
hash_x64_override="${OPENCODE_SHA256_X64_BASELINE-}"
hash_arm64_override="${OPENCODE_SHA256_ARM64-}"
repo_override="${OPENCODE_GITHUB_REPO-}"

detect_default_platform() {
  local arch
  case "$(uname -m)" in
    x86_64|amd64)
      arch=amd64
      ;;
    aarch64|arm64)
      arch=arm64
      ;;
    *)
      echo "Unsupported host architecture: $(uname -m)" >&2
      echo "Supported architectures: x86_64/amd64, aarch64/arm64" >&2
      exit 1
      ;;
  esac

  # This image runs on Linux containers, even for macOS or other host OSes.
  echo "linux/${arch}"
}

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

user_platform=""
build_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform=* )
      user_platform="${1#--platform=}"
      build_args+=("$1")
      shift
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        echo "--platform requires an argument" >&2
        exit 1
      fi
      user_platform="$2"
      build_args+=("$1" "$2")
      shift 2
      ;;
    *)
      build_args+=("$1")
      shift
      ;;
  esac
done

default_platform="$(detect_default_platform)"
default_version="${OPENCODE_VERSION-1.2.9}"
default_sha256_x64="${OPENCODE_SHA256_X64_BASELINE-18d433f3a5685a056701cdd93d32e28f239fa04847fcce6f5b83e35ee36fcb79}"
default_sha256_arm64="${OPENCODE_SHA256_ARM64-3d989ea59c542da2b96ed2484524bce254719fa470da85fed6a631a472ac47e5}"
default_repo="${OPENCODE_GITHUB_REPO-anomalyco/opencode}"

IMAGE_NAME="${image_name_override:-${IMAGE_NAME:-opencode-sandbox:dev}}"
DOCKERFILE="${dockerfile_override:-${DOCKERFILE:-Dockerfile}}"
OPENCODE_VERSION="${version_override:-${OPENCODE_VERSION:-$default_version}}"
OPENCODE_TARGETPLATFORM="${platform_override:-${user_platform:-${OPENCODE_TARGETPLATFORM:-$default_platform}}}"
OPENCODE_SHA256_X64_BASELINE="${hash_x64_override:-${OPENCODE_SHA256_X64_BASELINE:-$default_sha256_x64}}"
OPENCODE_SHA256_ARM64="${hash_arm64_override:-${OPENCODE_SHA256_ARM64:-$default_sha256_arm64}}"
OPENCODE_GITHUB_REPO="${repo_override:-${OPENCODE_GITHUB_REPO:-$default_repo}}"

case "${OPENCODE_TARGETPLATFORM}" in
  linux/amd64|amd64|linux/arm64|arm64)
    :
    ;;
  *)
    echo "Unsupported OPENCODE_TARGETPLATFORM: ${OPENCODE_TARGETPLATFORM}" >&2
    echo "Supported values: linux/amd64, linux/arm64" >&2
    exit 1
    ;;
esac

case "${OPENCODE_VERSION}" in
  1.2.9)
    :
    ;;
  *)
    if [[ -z "${OPENCODE_SHA256_X64_BASELINE}" || -z "${OPENCODE_SHA256_ARM64}" ]]; then
      echo "Set OPENCODE_SHA256_X64_BASELINE and OPENCODE_SHA256_ARM64 for version ${OPENCODE_VERSION}." >&2
      exit 1
    fi
    ;;
esac

if [[ -z "$user_platform" ]]; then
  build_args+=("--platform" "$OPENCODE_TARGETPLATFORM")
fi

docker build \
  --progress=plain \
  --tag "$IMAGE_NAME" \
  --build-arg "OPENCODE_VERSION=$OPENCODE_VERSION" \
  --build-arg "OPENCODE_TARGETPLATFORM=$OPENCODE_TARGETPLATFORM" \
  --build-arg "OPENCODE_SHA256_X64_BASELINE=$OPENCODE_SHA256_X64_BASELINE" \
  --build-arg "OPENCODE_SHA256_ARM64=$OPENCODE_SHA256_ARM64" \
  --build-arg "OPENCODE_GITHUB_REPO=$OPENCODE_GITHUB_REPO" \
  -f "$DOCKERFILE" \
  "${build_args[@]}" \
  .
