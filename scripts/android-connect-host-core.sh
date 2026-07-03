#!/usr/bin/env bash
# Shared host ADB connect logic for the Android sandbox profile.
# Source this file or run directly (best-effort connect + device listing).

ADB_HOST="${ADB_HOST:-host.docker.internal}"
ADB_PORT="${ADB_PORT:-5555}"

android_adb_restart_server() {
  adb kill-server >/dev/null 2>&1 || true
  adb start-server
}

android_adb_connect_host() {
  android_adb_restart_server
  adb connect "${ADB_HOST}:${ADB_PORT}" 2>&1
}

android_adb_count_ready_devices() {
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device" { count++ } END { print count+0 }'
}

android_adb_list_devices() {
  adb devices
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  android_adb_connect_host || true
  android_adb_list_devices
  count="$(android_adb_count_ready_devices)"
  if [[ "$count" -gt 0 ]]; then
    exit 0
  fi
  exit 1
fi
