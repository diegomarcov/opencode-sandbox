#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${BUILD_ENV_FILE:-${SCRIPT_DIR}/build.env}"

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [docker build flags]
  ./build.sh --fetch-hashes [--write-hashes]

Environment variables override build values and pass through to Docker:
  OPENCODE_VERSION, OPENCODE_SHA256_X64_BASELINE,
  OPENCODE_SHA256_ARM64, OPENCODE_GITHUB_REPO,
  OPENCODE_TARGETPLATFORM, SANDBOX_ENV, IMAGE_NAME,
  IMAGE_NAME_PYTHON, IMAGE_NAME_OPENCODE, IMAGE_NAME_ANDROID, DOCKERFILE,
  ANDROID_SDK_VERSION, ANDROID_BUILD_TOOLS, ANDROID_PLATFORM,
  ANDROID_EMULATOR_IMAGE_AMD64, ANDROID_EMULATOR_IMAGE_ARM64,
  ANDROID_INSTALL_EMULATOR

Options:
  --platform <plat>       Same as --platform for docker build
  --platform=<plat>       Same as --platform for docker build
  --sandbox-env <env>     Build environment profile (opencode|python|android)
  --sandbox-env=<env>     Build environment profile (opencode|python|android)
  --target <stage>        Docker build stage target (opencode|python|android)
  --target=<stage>        Docker build stage target (opencode|python|android)
  --fetch-hashes          Download both release artifacts and print SHA-256 hashes for OPENCODE_VERSION
  --write-hashes          Update build.env with fetched hashes (use with --fetch-hashes)
  -h, --help              Show this help

This is a pass-through wrapper: any unrecognized flags are forwarded to docker build.
EOF
}

error() {
  printf 'error: %s\n' "$1" >&2
}

validate_hash() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9a-fA-F]{64}$ ]]; then
    error "${name} must be a 64-char SHA-256 hex string"
    return 1
  fi
}

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_sandbox_env() {
  local sandbox_env="$(to_lower "$1")"
  case "$sandbox_env" in
    opencode|python|android)
      return 0
      ;;
    *)
      error "Unsupported SANDBOX_ENV: ${sandbox_env}"
      error "Supported values: opencode, python, android"
      return 1
      ;;
  esac
}

fetch_hashes() {
  local artifact="$1"
  local tmp_file
  local hash
  local url

  tmp_file="$(mktemp)"
  url="https://github.com/${OPENCODE_GITHUB_REPO}/releases/download/v${OPENCODE_VERSION}/${artifact}"

  curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors -o "$tmp_file" "$url"
  hash="$(sha256sum "$tmp_file" | awk '{print $1}')"
  rm -f "$tmp_file"
  printf '%s' "$hash"
}

write_hashes_to_env() {
  local env_file="$1"
  local x64_hash="$2"
  local arm64_hash="$3"

  if [[ ! -w "$env_file" ]]; then
    error "Cannot write hashes to ${env_file}: file is not writable"
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  awk -v version="$OPENCODE_VERSION" -v hash_x64="$x64_hash" -v hash_arm64="$arm64_hash" '
    BEGIN { found_version=0; found_hash_x64=0; found_hash_arm64=0 }
    /^OPENCODE_VERSION=/ { print "OPENCODE_VERSION=" version; found_version=1; next }
    /^OPENCODE_SHA256_X64_BASELINE=/ { print "OPENCODE_SHA256_X64_BASELINE=" hash_x64; found_hash_x64=1; next }
    /^OPENCODE_SHA256_ARM64=/ { print "OPENCODE_SHA256_ARM64=" hash_arm64; found_hash_arm64=1; next }
    { print }
    END {
      if (!found_version) { print "OPENCODE_VERSION=" version }
      if (!found_hash_x64) { print "OPENCODE_SHA256_X64_BASELINE=" hash_x64 }
      if (!found_hash_arm64) { print "OPENCODE_SHA256_ARM64=" hash_arm64 }
    }
  ' "$env_file" > "$tmp_file"

  mv "$tmp_file" "$env_file"
}

image_name_override="${IMAGE_NAME-}"
sandbox_env_override="${SANDBOX_ENV-}"
dockerfile_override="${DOCKERFILE-}"
version_override="${OPENCODE_VERSION-}"
platform_override="${OPENCODE_TARGETPLATFORM-}"
hash_x64_override="${OPENCODE_SHA256_X64_BASELINE-}"
hash_arm64_override="${OPENCODE_SHA256_ARM64-}"
repo_override="${OPENCODE_GITHUB_REPO-}"
sandbox_env_input=""
sandbox_target_input=""

fetch_hashes_mode="false"
write_hashes_mode="false"

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
    --sandbox-env=*)
      sandbox_env_input="${1#--sandbox-env=}"
      if [[ -z "$sandbox_env_input" ]]; then
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
      sandbox_env_input="$2"
      shift 2
      ;;
    --target=*)
      sandbox_target_input="${1#--target=}"
      if [[ -z "$sandbox_target_input" ]]; then
        echo "--target requires a stage value" >&2
        exit 1
      fi
      shift
      ;;
    --target)
      if [[ $# -lt 2 ]]; then
        echo "--target requires a stage value" >&2
        exit 1
      fi
      sandbox_target_input="$2"
      shift 2
      ;;
    --fetch-hashes)
      fetch_hashes_mode="true"
      shift
      ;;
    --write-hashes)
      write_hashes_mode="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
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
default_sandbox_env="${SANDBOX_ENV-opencode}"
default_image_opencode="${IMAGE_NAME_OPENCODE:-${IMAGE_NAME:-opencode-sandbox:dev}}"
default_image_python="${IMAGE_NAME_PYTHON:-opencode-sandbox-python:dev}"
default_image_android="${IMAGE_NAME_ANDROID:-opencode-sandbox-android:dev}"
default_android_sdk_version="${ANDROID_SDK_VERSION:-11076708}"
default_android_build_tools="${ANDROID_BUILD_TOOLS:-34.0.0}"
default_android_platform="${ANDROID_PLATFORM:-android-34}"
default_android_emulator_image_amd64="${ANDROID_EMULATOR_IMAGE_AMD64:-"system-images;android-34;google_apis;x86_64"}"
default_android_emulator_image_arm64="${ANDROID_EMULATOR_IMAGE_ARM64:-"system-images;android-34;google_apis;arm64-v8a"}"
default_android_install_emulator="${ANDROID_INSTALL_EMULATOR:-false}"

DOCKERFILE="${dockerfile_override:-${DOCKERFILE:-Dockerfile}}"
OPENCODE_VERSION="${version_override:-${OPENCODE_VERSION:-$default_version}}"
OPENCODE_TARGETPLATFORM="${platform_override:-${user_platform:-${OPENCODE_TARGETPLATFORM:-$default_platform}}}"
OPENCODE_SHA256_X64_BASELINE="${hash_x64_override:-${OPENCODE_SHA256_X64_BASELINE:-$default_sha256_x64}}"
OPENCODE_SHA256_ARM64="${hash_arm64_override:-${OPENCODE_SHA256_ARM64:-$default_sha256_arm64}}"
OPENCODE_GITHUB_REPO="${repo_override:-${OPENCODE_GITHUB_REPO:-$default_repo}}"
if [[ -n "$sandbox_env_input" ]]; then
  SANDBOX_ENV="$(to_lower "$sandbox_env_input")"
elif [[ -n "$sandbox_env_override" ]]; then
  SANDBOX_ENV="$(to_lower "$sandbox_env_override")"
elif [[ -n "$sandbox_target_input" ]]; then
  SANDBOX_ENV="$(to_lower "$sandbox_target_input")"
elif [[ -z "${SANDBOX_ENV-}" ]]; then
  SANDBOX_ENV="$(to_lower "$default_sandbox_env")"
fi

if ! validate_sandbox_env "$SANDBOX_ENV"; then
  exit 1
fi

# Android profile uses the host-native platform so OpenCode runs natively.
# Google SDK natives (adb, aapt2) are still x86_64; the image runs them via
# qemu-user on arm64 (see Dockerfile android stage).
if [[ "$SANDBOX_ENV" == "android" && -z "$platform_override" && -z "$user_platform" ]]; then
  case "$(uname -m)" in
    aarch64|arm64)
      echo "Note: android profile uses linux/arm64 on arm64 hosts (OpenCode native; x86_64 SDK tools via qemu-user)." >&2
      ;;
  esac
fi

if [[ -n "$sandbox_target_input" ]]; then
  sandbox_target_input="$(to_lower "$sandbox_target_input")"
  if [[ "$sandbox_target_input" != "$SANDBOX_ENV" ]]; then
    error "Mismatched profile and build target: --sandbox-env=$SANDBOX_ENV and --target=$sandbox_target_input"
    error "Set --sandbox-env and --target to the same value, or omit --target to use the profile default"
    exit 1
  fi
fi

SANDBOX_TARGET="${sandbox_target_input:-$SANDBOX_ENV}"

if [[ -n "$image_name_override" ]]; then
  IMAGE_NAME="$image_name_override"
else
  case "$SANDBOX_ENV" in
    opencode)
      IMAGE_NAME="$default_image_opencode"
      ;;
    python)
      IMAGE_NAME="$default_image_python"
      ;;
    android)
      IMAGE_NAME="$default_image_android"
      ;;
  esac
fi

ANDROID_SDK_VERSION="${ANDROID_SDK_VERSION:-$default_android_sdk_version}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-$default_android_build_tools}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-$default_android_platform}"
ANDROID_EMULATOR_IMAGE_AMD64="${ANDROID_EMULATOR_IMAGE_AMD64:-$default_android_emulator_image_amd64}"
ANDROID_EMULATOR_IMAGE_ARM64="${ANDROID_EMULATOR_IMAGE_ARM64:-$default_android_emulator_image_arm64}"
ANDROID_INSTALL_EMULATOR="${ANDROID_INSTALL_EMULATOR:-$default_android_install_emulator}"

if [[ "$fetch_hashes_mode" == "true" ]]; then
  OPENCODE_VERSION="${OPENCODE_VERSION#v}"
  if [[ -z "$OPENCODE_VERSION" ]]; then
    error "OPENCODE_VERSION is required for --fetch-hashes"
    exit 1
  fi
  if [[ -z "$OPENCODE_GITHUB_REPO" ]]; then
    error "OPENCODE_GITHUB_REPO is required for --fetch-hashes"
    exit 1
  fi

  echo "Fetching release archives for v${OPENCODE_VERSION} from ${OPENCODE_GITHUB_REPO}"

  x64_hash="$(fetch_hashes opencode-linux-x64-baseline.tar.gz)"
  arm64_hash="$(fetch_hashes opencode-linux-arm64.tar.gz)"

  validate_hash "OPENCODE_SHA256_X64_BASELINE" "$x64_hash"
  validate_hash "OPENCODE_SHA256_ARM64" "$arm64_hash"

  echo
  echo "Export these values into $(printf '%q' "$ENV_FILE"):"
  echo "OPENCODE_VERSION=${OPENCODE_VERSION}"
  echo "OPENCODE_SHA256_X64_BASELINE=${x64_hash}"
  echo "OPENCODE_SHA256_ARM64=${arm64_hash}"

  if [[ "$write_hashes_mode" == "true" ]]; then
    write_hashes_to_env "$ENV_FILE" "$x64_hash" "$arm64_hash"
    echo "Updated ${ENV_FILE}"
  fi

  if [[ "$write_hashes_mode" == "false" ]]; then
    echo "Tip: rerun with --write-hashes to persist these values automatically."
  fi

  exit 0
fi

if [[ "$write_hashes_mode" == "true" ]]; then
  error "--write-hashes requires --fetch-hashes"
  exit 1
fi

if [[ -z "${OPENCODE_VERSION}" ]]; then
  error "Missing OPENCODE_VERSION"
  exit 1
fi

if [[ -z "${OPENCODE_SHA256_X64_BASELINE}" ]]; then
  error "Missing OPENCODE_SHA256_X64_BASELINE"
  exit 1
fi

if [[ -z "${OPENCODE_SHA256_ARM64}" ]]; then
  error "Missing OPENCODE_SHA256_ARM64"
  exit 1
fi

if [[ -z "${OPENCODE_GITHUB_REPO}" ]]; then
  error "Missing OPENCODE_GITHUB_REPO"
  exit 1
fi

validate_hash "OPENCODE_SHA256_X64_BASELINE" "$OPENCODE_SHA256_X64_BASELINE"
validate_hash "OPENCODE_SHA256_ARM64" "$OPENCODE_SHA256_ARM64"

OPENCODE_VERSION="${OPENCODE_VERSION#v}"

case "${OPENCODE_TARGETPLATFORM}" in
  linux/amd64|amd64|linux/arm64|arm64)
    :
    ;;
  *)
    error "Unsupported OPENCODE_TARGETPLATFORM: ${OPENCODE_TARGETPLATFORM}"
    error "Supported values: linux/amd64, linux/arm64"
    exit 1
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
  --build-arg "SANDBOX_ENV=$SANDBOX_ENV" \
  --build-arg "ANDROID_SDK_VERSION=$ANDROID_SDK_VERSION" \
  --build-arg "ANDROID_BUILD_TOOLS=$ANDROID_BUILD_TOOLS" \
  --build-arg "ANDROID_PLATFORM=$ANDROID_PLATFORM" \
  --build-arg "ANDROID_EMULATOR_IMAGE_AMD64=$ANDROID_EMULATOR_IMAGE_AMD64" \
  --build-arg "ANDROID_EMULATOR_IMAGE_ARM64=$ANDROID_EMULATOR_IMAGE_ARM64" \
  --build-arg "ANDROID_INSTALL_EMULATOR=$ANDROID_INSTALL_EMULATOR" \
  --target "$SANDBOX_TARGET" \
  -f "$DOCKERFILE" \
  "${build_args[@]}" \
  .
