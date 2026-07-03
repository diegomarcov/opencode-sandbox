#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=android-connect-host-core.sh
source "${SCRIPT_DIR}/android-connect-host-core.sh"

android_adb_connect_host
android_adb_list_devices
