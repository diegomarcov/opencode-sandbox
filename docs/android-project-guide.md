# Android project guide

Step-by-step instructions for working on an Android project with OpenCode inside the sandbox. The primary workflow is a **single command** that connects to your host emulator, prepares the Android environment, and opens the OpenCode console.

This guide assumes you are in the `opencode-sandbox` repository root unless noted otherwise.

## What you need first

- **Docker Desktop** running (macOS or Linux).
- **An Android project** on your host machine — a directory that contains `gradlew` (or `gradlew.bat`) and an `app/` module. Example:

  ```text
  /Users/you/AndroidStudioProjects/my-app/
    ├── gradlew
    ├── settings.gradle.kts
    └── app/
  ```

- **A host emulator or physical device** (recommended on macOS). The sandbox connects to it over the network; it does not replace Android Studio for starting the emulator UI.

## How the sandbox maps your project

`run.sh` mounts your chosen host directory at `/work` inside the container:

| Host | Container |
|------|-----------|
| `/path/to/your/android-project` | `/work` |
| `~/.local/share/opencode-sandbox/state` (fallback) or Docker volume `opencode-home` | `/home/opencode` (Gradle cache, Android config) |

Each `./run.sh` invocation starts one ephemeral container (`docker run --rm`). For day-to-day work, run **one OpenCode session** and let OpenCode (or a `bash` shell in the same session) run Gradle and `adb` commands — ADB stays connected for the whole session.

## Step 1 — Build the Android sandbox image (one time)

From the `opencode-sandbox` directory:

```bash
SANDBOX_ENV=android ./build.sh
```

On Apple Silicon, the Android image is built for `linux/amd64` on purpose (Google's Linux SDK tools are x86_64). Docker Desktop emulates that platform. You may see a warning like:

```text
WARNING: The requested image's platform (linux/amd64) does not match the detected host platform (linux/arm64/v8)
```

That is expected and safe to ignore if `adb version` works in Step 2.

## Step 2 — Verify the image

Still from `opencode-sandbox`:

```bash
SANDBOX_ENV=android ./run.sh adb version
SANDBOX_ENV=android ./run.sh java -version
```

Both should print version info without errors. Run these **one at a time** (see [Troubleshooting](#troubleshooting)).

## Step 3 — Start an emulator or device on the host

The default mode is **host emulator** (`ANDROID_EMULATOR_MODE=host`). The emulator runs on your Mac/Linux host; the sandbox connects via `adb connect` at session start.

### Physical device or already-running emulator

On the **host** (outside Docker), enable TCP debugging on port 5555:

```bash
adb -e tcpip 5555
```

For a USB device, use `adb -d tcpip 5555` instead of `-e`.

### Start a new emulator on a fixed port

```bash
emulator -avd <your-avd-name> -port 5555
```

Leave the emulator running before you start the sandbox session.

## Step 4 — Start OpenCode on your Android project (primary workflow)

Pick the absolute path to your project root (the folder that contains `gradlew`):

```bash
export ANDROID_PROJECT=/Users/you/AndroidStudioProjects/my-app

SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT"
```

Omitting a command defaults to **OpenCode**. The container runs `android-session-init.sh` first, which:

1. Connects ADB to the host emulator (`host.docker.internal:5555` by default)
2. Validates the project at `/work`
3. Prints a session summary (SDK, ADB status, Gradle hints)
4. Launches OpenCode

From OpenCode, ask it to build, install, or debug — for example `./gradlew assembleDebug`, `./gradlew installDebug`, or `adb logcat`. All commands run in the **same container session**, so the host emulator stays connected.

Optional: seed OpenCode project rules on first run (only if `/work/AGENTS.md` does not exist):

```bash
SANDBOX_BOOTSTRAP_AGENTS=true SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT"
```

Use an interactive terminal (not a background task runner) so stdin/stdout stay attached to OpenCode.

### Session summary example

```text
Android sandbox session ready
  Project:  /work (Android project detected)
  SDK:      /opt/android-sdk
  ADB:      host.docker.internal:5555 → device
  Gradle:   ./gradlew (debug build: ./gradlew assembleDebug)
```

If ADB shows `WARNING: no device`, the host emulator is not reachable — fix Step 3, then start a new session.

## What `android-session-init.sh` sets up

When session init runs, the container already has:

| Item | Location / value |
|------|------------------|
| Project root | `/work` (your host project) |
| Android SDK | `/opt/android-sdk` (`ANDROID_HOME`, `ANDROID_SDK_ROOT`) |
| Gradle cache | `/home/opencode/.gradle` |
| Host emulator | Connected via `adb connect` to `${ADB_HOST}:${ADB_PORT}` (default `host.docker.internal:5555`) |
| Helper scripts | `android-connect-host.sh`, `android-avd-init.sh`, `android-emulator-start.sh` on `PATH` |

OpenCode and any shell commands you run in the same session inherit this environment. You do not need to run `android-connect-host.sh` manually before Gradle or `adb` commands.

## Step 5 — Alternative entry points

| Goal | Command |
|------|---------|
| OpenCode (default) | `SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT"` |
| Interactive shell (ADB pre-connected) | `SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" bash` |
| One-off Gradle build | `SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" ./gradlew assembleDebug` |
| One-off install | `SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" ./gradlew installDebug` |

One-off commands also run session init (connect + summary) before the command. Each `./run.sh` call is still a separate container — for multiple Gradle/adb steps, prefer one OpenCode or `bash` session.

### Shell alias (optional)

```bash
alias my-app-sandbox='cd "/path/to/opencode-sandbox" && SANDBOX_ENV=android ./run.sh --workdir /Users/you/AndroidStudioProjects/my-app'

my-app-sandbox          # opens OpenCode
my-app-sandbox bash     # interactive shell with ADB ready
```

## Advanced — manual ADB diagnostics

Session init connects automatically. Use these only for troubleshooting:

```bash
SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" android-connect-host.sh
SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" adb devices
```

Override the host/port if needed:

```bash
ADB_HOST=host.docker.internal ADB_PORT=5555 \
  SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" android-connect-host.sh
```

Skip session init entirely (raw command, no auto-connect):

```bash
ANDROID_SESSION_INIT=false SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT" adb devices
```

## Quick reference — full workflow (copy and adapt)

Replace `/Users/you/AndroidStudioProjects/my-app` with your project path.

```bash
# 1. One-time build (from opencode-sandbox repo)
SANDBOX_ENV=android ./build.sh

# 2. On the host: start emulator + enable TCP
emulator -avd MyAvd -port 5555
# or, if already running: adb -e tcpip 5555

# 3. Start OpenCode on your Android project
export ANDROID_PROJECT=/Users/you/AndroidStudioProjects/my-app
SANDBOX_ENV=android ./run.sh --workdir "$ANDROID_PROJECT"

# 4. From OpenCode, run builds/installs (same session — no manual adb connect)
#    e.g. ./gradlew assembleDebug, ./gradlew installDebug, adb logcat
```

## Troubleshooting

### `Conflict. The container name "/opencode-sandbox" is already in use`

You started two `./run.sh` commands at the same time. Each run tries to use the fixed name `opencode-sandbox`. Wait for one to finish before starting another.

If a container is stuck:

```bash
docker rm -f opencode-sandbox
```

Then retry a single command.

### `container is marked for removal and cannot be started`

Usually the same race as above — a previous container is still shutting down. Wait a few seconds, run `docker rm -f opencode-sandbox`, and try again with **one** command.

### Session shows `WARNING: no device`

1. Confirm the host emulator is running and `adb -e tcpip 5555` succeeded on the host.
2. Check `ADB_HOST` and `ADB_PORT` match your setup (defaults: `host.docker.internal:5555`).
3. Start a **new** sandbox session after fixing the host emulator.

### `No connected devices` during `installDebug`

Same as above — host emulator not reachable when the session started. Restart the session after enabling TCP on the host. Compile-only tasks (`assembleDebug`) do not need a device.

### `sdk.dir` Gradle warning

If your project's `local.properties` points at a host macOS SDK path, Gradle may warn that the directory does not exist. The sandbox uses `/opt/android-sdk` via `ANDROID_HOME`; the warning is expected and safe to ignore if builds succeed.

### Gradle permission errors on Linux

On Linux, `run.sh` defaults `CONTAINER_UID`/`CONTAINER_GID` to your host user so `/work` stays writable. On macOS the default is `10001`; project files are still writable via the mount.

### `qemu-x86_64: Could not open '/lib64/ld-linux-x86-64.so.2'`

The Android image was built for the wrong platform. Rebuild:

```bash
SANDBOX_ENV=android ./build.sh --platform linux/amd64
```

On arm64 hosts, `./build.sh` normally selects `linux/amd64` for the Android profile automatically.

### SDK version mismatch in the project

The sandbox ships pinned SDK components from `build.env` (`ANDROID_PLATFORM`, `ANDROID_BUILD_TOOLS`, etc.). If your project requires a newer API level or build-tools version, either align the project with those pins or rebuild the image after updating `build.env`.

## Related docs

- [README.md](../README.md) — build options, environment variables, persistence
- [environments/README.md](../environments/README.md) — profile overview (`opencode`, `python`, `android`)
