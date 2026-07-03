# Android sandbox (OpenCode)

This project runs inside the opencode-sandbox Android profile. The working directory is `/work`.

## First session (required)

When this project is first opened in the sandbox (or when this file was just created), proactively set it up. Do **not** ask the user to run build or install commands — execute them yourself:

1. `adb devices` — confirm a device/emulator is connected
2. `./gradlew assembleDebug` — build the debug APK; fix any errors
3. `./gradlew installDebug` — install on the connected device
4. If install or app startup fails, use `adb logcat` (optionally filtered by the app package) to diagnose and fix

After the first successful install, keep using these commands whenever you change code that should be verified on device.

## Build and run

- Debug APK: `./gradlew assembleDebug`
- Install on the connected emulator/device: `./gradlew installDebug` (ADB is pre-connected at session start)
- Connected devices: `adb devices`
- Logs: `adb logcat`

## Environment

- Android SDK: `/opt/android-sdk` (`ANDROID_HOME`, `ANDROID_SDK_ROOT`)
- Gradle cache: `/home/opencode/.gradle` (persists across sessions)
- Host emulator is reached via `adb connect` to `host.docker.internal:5555` at session start

## Notes

- Do not change `sdk.dir` in `local.properties` to a host macOS path; the sandbox uses `/opt/android-sdk`. A Gradle warning about `sdk.dir` pointing to a missing directory is expected and safe to ignore.
- If `installDebug` fails with "No connected devices", the host emulator may not be running or TCP may be disabled. On the host: `adb -e tcpip 5555`, then restart the sandbox session.
