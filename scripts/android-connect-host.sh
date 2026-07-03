#!/usr/bin/env bash
set -euo pipefail

ADB_HOST="${ADB_HOST:-host.docker.internal}"
ADB_PORT="${ADB_PORT:-5555}"

adb kill-server >/dev/null 2>&1 || true
adb start-server
adb connect "${ADB_HOST}:${ADB_PORT}"
adb devices
