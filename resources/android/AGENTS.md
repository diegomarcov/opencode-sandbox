# Android sandbox (OpenCode)

This project runs inside the opencode-sandbox Android profile. The working directory is `/work`.

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
