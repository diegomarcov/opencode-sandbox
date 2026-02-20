#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROFILE_PATH="${1:-$PROJECT_ROOT/apparmor/opencode-sandbox}"

if [[ "$(uname -s)" == "Darwin" ]]; then
  echo "AppArmor is not supported on macOS hosts (Docker Desktop ignores AppArmor profiles)."
  echo "Nothing to load. Continuing without changes."
  exit 0
fi

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "AppArmor profile not found: $PROFILE_PATH" >&2
  echo "Usage: $0 [path-to-profile]" >&2
  exit 1
fi

if ! command -v apparmor_parser >/dev/null 2>&1; then
  echo "apparmor_parser not found. Install apparmor-tools (or equivalent) first." >&2
  exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Root privileges are required to load AppArmor profiles." >&2
    echo "Run this command as root, or install sudo." >&2
    exit 1
  fi
  SUDO="sudo"
else
  SUDO=""
fi

PROFILE_NAME="$(awk '/^profile[[:space:]]+/ {print $2; exit}' "$PROFILE_PATH" | sed 's/[[:space:]]*{//' )"
PROFILE_NAME="${PROFILE_NAME:-$(basename "$PROFILE_PATH")}"

if ! "$SUDO" apparmor_parser -r -W "$PROFILE_PATH"; then
  echo "Failed to load AppArmor profile: $PROFILE_NAME" >&2
  exit 1
fi

echo "Loaded AppArmor profile: $PROFILE_NAME"
