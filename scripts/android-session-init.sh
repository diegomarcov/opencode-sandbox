#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android-connect-host-core.sh
source "${SCRIPT_DIR}/android-connect-host-core.sh"

ANDROID_EMULATOR_MODE="${ANDROID_EMULATOR_MODE:-host}"
SANDBOX_BOOTSTRAP_AGENTS="${SANDBOX_BOOTSTRAP_AGENTS:-true}"
AGENTS_TEMPLATE="/usr/share/opencode-sandbox/android/AGENTS.md"
WORK_DIR="/work"
FIRST_SESSION_MARKER="${WORK_DIR}/.opencode-sandbox-initialized"
FIRST_SESSION_PROMPT='Perform first-session Android setup for this project now:
1. Run `adb devices` and confirm a device is connected.
2. Run `./gradlew assembleDebug` and fix any build errors.
3. Run `./gradlew installDebug` to install the app on the device.
4. If install or startup fails, use `adb logcat` to diagnose.
Do not ask the user to run these commands — execute them yourself.'

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  case "$(to_lower "$1")" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

assert_opencode_usable() {
  local help_head
  help_head="$(opencode --help 2>&1 | head -n 1 || true)"
  if printf '%s' "$help_head" | grep -qi 'Usage: bun'; then
    echo "Error: /usr/local/bin/opencode is falling back to Bun instead of OpenCode." >&2
    echo "  This usually means the android image was built for the wrong platform." >&2
    echo "  Rebuild with: SANDBOX_ENV=android ./build.sh" >&2
    echo "  On Apple Silicon, the android image must be linux/arm64 (native OpenCode)." >&2
    exit 1
  fi
}

adb_status="no device"
adb_ready_count=0
first_session=false

bootstrap_adb_host() {
  android_adb_connect_host || true
  adb_ready_count="$(android_adb_count_ready_devices)"
  if [[ "$adb_ready_count" -gt 0 ]]; then
    adb_status="device"
  else
    adb_status="WARNING: no device"
    echo "Warning: no ADB device in 'device' state at ${ADB_HOST}:${ADB_PORT}." >&2
    echo "  On the host, ensure the emulator is running and run: adb -e tcpip ${ADB_PORT}" >&2
  fi
}

bootstrap_adb_container() {
  adb start-server 2>/dev/null || true
  adb_ready_count="$(android_adb_count_ready_devices)"
  if [[ "$adb_ready_count" -gt 0 ]]; then
    adb_status="device (local)"
  else
    adb_status="WARNING: no local device"
    echo "Warning: no in-container emulator detected." >&2
    echo "  Start one in another terminal: ANDROID_EMULATOR_MODE=container ./run.sh android-emulator-start.sh" >&2
    echo "  Or use host mode (default): ANDROID_EMULATOR_MODE=host" >&2
  fi
}

case "$(to_lower "$ANDROID_EMULATOR_MODE")" in
  host)
    bootstrap_adb_host
    ;;
  container)
    bootstrap_adb_container
    ;;
  *)
    echo "Invalid ANDROID_EMULATOR_MODE: ${ANDROID_EMULATOR_MODE}" >&2
    exit 1
    ;;
esac

project_note="/work"
if [[ -x "${WORK_DIR}/gradlew" ]]; then
  project_note="/work (Android project detected)"
elif [[ -f "${WORK_DIR}/gradlew" ]]; then
  project_note="/work (gradlew present but not executable)"
  echo "Warning: ${WORK_DIR}/gradlew exists but is not executable." >&2
else
  project_note="/work (no gradlew — OpenCode may still run)"
  echo "Warning: no ${WORK_DIR}/gradlew found; Gradle builds will not work until a project is mounted." >&2
fi

if is_true "$SANDBOX_BOOTSTRAP_AGENTS" && [[ -x "${WORK_DIR}/gradlew" || -f "${WORK_DIR}/gradlew" ]]; then
  if [[ ! -f "${WORK_DIR}/AGENTS.md" && -f "$AGENTS_TEMPLATE" ]]; then
    cp "$AGENTS_TEMPLATE" "${WORK_DIR}/AGENTS.md"
    echo "Created ${WORK_DIR}/AGENTS.md from sandbox template."
  fi
  if [[ ! -f "$FIRST_SESSION_MARKER" ]]; then
    first_session=true
    # Mark before launching OpenCode so a retry does not re-run setup automatically.
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$FIRST_SESSION_MARKER"
    echo "First-session setup enabled (marker: ${FIRST_SESSION_MARKER})."
  fi
fi

cat <<EOF

Android sandbox session ready
  Project:  ${project_note}
  SDK:      ${ANDROID_HOME:-/opt/android-sdk}
  ADB:      ${ADB_HOST}:${ADB_PORT} → ${adb_status}
  Gradle:   ./gradlew (debug build: ./gradlew assembleDebug)

EOF

launch_opencode() {
  assert_opencode_usable
  if [[ "$first_session" == true ]]; then
    echo "First project setup: OpenCode will build and install the debug app."
    exec opencode --prompt "$FIRST_SESSION_PROMPT"
  fi
  exec opencode
}

# Default path from run.sh is `android-session-init.sh opencode` (no extra args).
if [[ "$#" -eq 0 || ( "$#" -eq 1 && "$1" == "opencode" ) ]]; then
  launch_opencode
fi

if [[ "$1" == "opencode" ]]; then
  assert_opencode_usable
fi

exec "$@"
