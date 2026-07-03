# Opencode Sandbox Container

This directory contains a hardened Docker image and a small launcher script for running `opencode` in a safer local-dev container.

## What is hardened right now (Phase 1)

- Container runs as a non-root user (`CONTAINER_UID`/`CONTAINER_GID`, defaulting to host UID/GID on Linux and `10001` on macOS)
- `no-new-privileges` is enabled
- All Linux capabilities are dropped (`--cap-drop=ALL`)
- Basic resource limits are enabled (`pids`, `memory`, `cpu`)
- Root filesystem can be read-only (`--read-only`) with writable tmpfs for `/tmp` and `/run`
- Optional AppArmor confinement is supported on Linux hosts via `APPARMOR_PROFILE`.
- Default seccomp confinement is enabled on macOS to add another Linux-container isolation layer while keeping `/connect` online.
- State mount is resilient by default (`STATE_INIT_MODE=auto` falls back to `STATE_BIND_DIR` when the state volume is not writable).

Networking is intentionally left enabled for now so flows like `/connect` can still work.

## Build

Build image:

```bash
./build.sh
```

Build a Python-focused environment (`python` profile):

```bash
SANDBOX_ENV=python ./build.sh
```

or explicitly pin the build stage:

```bash
./build.sh --sandbox-env python --target python
```

Build an Android-focused environment (`android` profile):

```bash
SANDBOX_ENV=android ./build.sh
```

or explicitly pin the build stage:

```bash
./build.sh --sandbox-env android --target android
```

Each profile builds a **separate image** (`opencode-sandbox:dev`, `opencode-sandbox-python:dev`, or `opencode-sandbox-android:dev`). You do not need to build the default `opencode` image first.

For in-container emulator support (large image), include emulator packages at build time:

```bash
ANDROID_INSTALL_EMULATOR=true SANDBOX_ENV=android ./build.sh
```

`--sandbox-env` and `--target` must match when both are set.

Supported values for `SANDBOX_ENV`:

- `opencode` (default): base `opencode` runtime
- `python`: same hardening model plus minimal Python toolchain (`uv`, `python3`, `python3-pip`, `python3-venv`) installed
- `android`: same base runtime plus Android SDK (JDK 17, `adb`, `sdkmanager`); see [Android profile](#android-profile) below

`build.sh` reads default values from `build.env`, so the version and hashes are kept centralized.

### Upgrading Opencode version

The normal workflow for version upgrades is:

1. Edit `build.env` values for
   - `OPENCODE_VERSION`
   - `OPENCODE_SHA256_X64_BASELINE`
   - `OPENCODE_SHA256_ARM64`
   and then run:

```bash
./build.sh
```

If you only know the new `OPENCODE_VERSION`, fetch hashes directly from GitHub first:

```bash
OPENCODE_VERSION=1.2.10 ./build.sh --fetch-hashes
```

Use `--write-hashes` to persist the fetched hashes into `build.env` in one shot:

```bash
OPENCODE_VERSION=1.2.10 ./build.sh --fetch-hashes --write-hashes
```

`build.sh` auto-selects the container target platform from the host architecture:
- Linux x86_64 -> `linux/amd64`
- Linux arm64 / aarch64 -> `linux/arm64`
- macOS arm64 (Apple Silicon) -> `linux/arm64`

The `android` profile uses that same host-native platform so OpenCode runs natively. Google's Android SDK natives (`adb`, `aapt2`, etc.) are still x86_64 on Linux; on arm64 images they run through `qemu-user-static` with x86_64 loader libs bundled in the image.

You can also pin a specific target platform for cross-compilation:

```bash
./build.sh --platform linux/amd64
```

You can point to a custom env file by setting `BUILD_ENV_FILE`:

```bash
BUILD_ENV_FILE=./build.env.local ./build.sh
```

You can pin a specific Opencode version by setting `OPENCODE_VERSION` and the matching hashes.

```bash
OPENCODE_VERSION=1.2.10 \
OPENCODE_TARGETPLATFORM=linux/amd64 \
OPENCODE_SHA256_X64_BASELINE=<sha256-for-x64-baseline> \
OPENCODE_SHA256_ARM64=<sha256-for-arm64> \
./build.sh
```

Tip: for regular x64/arm64 host builds, keep `build.sh` as-is and update hashes in `build.env` only. For cross-platform builds, also set `OPENCODE_TARGETPLATFORM` via env vars or `--platform`.

You can also edit `build.env` directly for persistent defaults.

```bash
vim build.env
```

`docker build` flags are still supported by passing them after `./build.sh`.

```bash
./build.sh --no-cache
```

## Run

If you want AppArmor enabled, load the provided profile first:

```bash
bash ./scripts/load-apparmor-profile.sh
```

On macOS this command is a no-op because Docker Desktop on mac does not expose AppArmor to the host VM.

Then run with the profile name:

```bash
APPARMOR_PROFILE=opencode-sandbox ./run.sh
```

You can also run with no AppArmor profile loaded:

```bash
./run.sh
```

If your host has an existing profile and you prefer that, set `APPARMOR_PROFILE` accordingly:

```bash
APPARMOR_PROFILE=docker-default ./run.sh
```

By default, `run.sh` launches `opencode` directly, so you can now do:

```bash
./run.sh
```

You can mount a different host repo into `/work` with `--workdir`:

```bash
./run.sh --workdir /path/to/other-repo
```

This is equivalent to setting `HOST_WORKDIR` directly:

```bash
HOST_WORKDIR=/path/to/other-repo ./run.sh
```

You can still pass a command when you need shell access or custom args:

```bash
./run.sh bash
```

```bash
./run.sh opencode --version
```

Use Python mode with the same command launcher:

```bash
SANDBOX_ENV=python ./run.sh python -V
SANDBOX_ENV=python ./run.sh uv --version
```

Or via CLI flag:

```bash
./run.sh --sandbox-env=python python -V
```

Use Android mode with the same command launcher:

```bash
SANDBOX_ENV=android ./run.sh adb version
SANDBOX_ENV=android ./run.sh java -version
SANDBOX_ENV=android ./run.sh bash
```

For Android projects, the recommended entry point is OpenCode with your project mounted — see [Android profile](#android-profile) and [docs/android-project-guide.md](docs/android-project-guide.md):

```bash
SANDBOX_ENV=android ./run.sh --workdir /path/to/android-project
```

Or via CLI flag:

```bash
./run.sh --sandbox-env=android adb version
```

See [Android profile](#android-profile) below for emulator workflows and Android-specific environment variables.

## Android profile

For a step-by-step walkthrough (pick a host project, connect an emulator, build with Gradle), see [docs/android-project-guide.md](docs/android-project-guide.md).

The `android` profile adds a pinned Android SDK (JDK 17, `adb`, `sdkmanager`, Gradle-friendly env vars), helper scripts for emulator workflows, and relaxed runtime defaults (`READ_ONLY_ROOTFS=false`, higher memory/CPU limits).

**Primary workflow:** point the sandbox at your Android project and start OpenCode. Session init connects to the host emulator and prepares the environment automatically:

```bash
# Host: emulator listening on TCP 5555 (see below)
SANDBOX_ENV=android ./run.sh --workdir /path/to/android-project
```

OpenCode then runs Gradle and `adb` commands in the same session — no manual `android-connect-host.sh` step.

### Session bootstrap

Every Android command (except diagnostic scripts) runs through `android-session-init.sh` first when `ANDROID_SESSION_INIT=true` (default). The init script:

- Connects ADB to the host emulator in `host` mode (`adb connect` to `ADB_HOST:ADB_PORT`)
- Validates that `/work` looks like an Android project
- Prints a session summary (SDK path, ADB status, Gradle hints)
- Runs your command — OpenCode by default, or `./gradlew`, `bash`, etc.

Set `ANDROID_SESSION_INIT=false` to skip bootstrap for raw debugging. By default the android profile sets `SANDBOX_BOOTSTRAP_AGENTS=true`, which copies a template `AGENTS.md` into `/work` on first run and starts OpenCode with a first-session prompt so the agent builds and installs the debug app (`assembleDebug` / `installDebug`) without asking you to run those commands manually.

Build the image first (see [Build](#build) above), then verify SDK tools:

```bash
SANDBOX_ENV=android ./run.sh adb version
SANDBOX_ENV=android ./run.sh java -version
```

### Mode A: host emulator (default)

Connect the container to an emulator or device running on the host. This is the recommended mode on macOS.

1. Start your host emulator listening on TCP port 5555. For example:

```bash
emulator -avd <name> -port 5555
```

If the emulator is already running, enable TCP listening on the host:

```bash
adb -e tcpip 5555
```

2. Start OpenCode on your project (session init connects ADB automatically):

```bash
SANDBOX_ENV=android ./run.sh --workdir /path/to/android-project
```

On first run for a project, the sandbox copies `AGENTS.md` into the project and starts OpenCode with a first-session prompt so the agent runs `adb devices`, `./gradlew assembleDebug`, and `./gradlew installDebug` itself. Set `SANDBOX_BOOTSTRAP_AGENTS=false` to skip that.

On Linux, `run.sh` adds `host.docker.internal` via Docker's host gateway. On macOS, Docker Desktop provides `host.docker.internal` by default.

For manual ADB diagnostics or custom host/port:

```bash
ADB_HOST=host.docker.internal ADB_PORT=5555 SANDBOX_ENV=android ./run.sh android-connect-host.sh
```

### Mode B: in-container emulator (opt-in)

Requires building with `ANDROID_INSTALL_EMULATOR=true`. Uses relaxed security (KVM device passthrough on Linux, higher resource limits).

```bash
ANDROID_INSTALL_EMULATOR=true SANDBOX_ENV=android ./build.sh

# Linux with /dev/kvm
ANDROID_EMULATOR_MODE=container SANDBOX_ENV=android ./run.sh android-avd-init.sh
ANDROID_EMULATOR_MODE=container SANDBOX_ENV=android ./run.sh android-emulator-start.sh
```

On macOS, in-container emulation has no KVM and is very slow. You must opt in explicitly:

```bash
ANDROID_EMULATOR_MODE=container ALLOW_SOFTWARE_EMULATOR=true SANDBOX_ENV=android ./run.sh android-emulator-start.sh
```

Load Android AppArmor profiles on Linux before running with AppArmor:

```bash
bash ./scripts/load-apparmor-profile.sh apparmor/opencode-sandbox-android
bash ./scripts/load-apparmor-profile.sh apparmor/opencode-sandbox-android-emulator
```

### Android environment overrides

In addition to the [general overrides](#useful-environment-overrides), the `android` profile supports:

- `IMAGE_NAME_ANDROID` (default `opencode-sandbox-android:dev`)
- `ANDROID_EMULATOR_MODE` (default `host`; options `host`, `container`)
- `ADB_HOST` (default `host.docker.internal`)
- `ADB_PORT` (default `5555`)
- `ANDROID_SESSION_INIT` (default `true`; runs `android-session-init.sh` before each command — connects host ADB and prints session summary)
- `SANDBOX_BOOTSTRAP_AGENTS` (default `true` for android, `false` otherwise; when `true`, copies `/usr/share/opencode-sandbox/android/AGENTS.md` to `/work/AGENTS.md` if missing and starts OpenCode with a first-session build/install prompt)
- `ALLOW_SOFTWARE_EMULATOR` (default `false`; required on macOS for container mode)
- `ANDROID_INSTALL_EMULATOR` (build-time; default `false`)
- `ANDROID_SDK_VERSION`, `ANDROID_BUILD_TOOLS`, `ANDROID_PLATFORM` (build-time pins in `build.env`)
- `ANDROID_EMULATOR_IMAGE_AMD64`, `ANDROID_EMULATOR_IMAGE_ARM64` (build-time system image pins in `build.env`)
- `AVD_NAME` (default `sandbox`; used by `android-avd-init.sh` and `android-emulator-start.sh`)
- `AVD_DEVICE` (default `pixel_6`; used by `android-avd-init.sh`)
- `EMULATOR_GPU` (default `swiftshader_indirect`; used by `android-emulator-start.sh`)
- `EMULATOR_NO_WINDOW` (default `true`; used by `android-emulator-start.sh`)

The `android` profile defaults to `READ_ONLY_ROOTFS=false`, `MEMORY_LIMIT=4g`, `CPU_LIMIT=2.0`, and `PIDS_LIMIT=512`.

### Troubleshooting

If OpenCode prints Bun's help text instead of starting the TUI, the android image is the wrong architecture (an amd64 OpenCode binary under qemu falls back to Bun). Rebuild for the host-native platform:

```bash
SANDBOX_ENV=android ./build.sh
```

On Apple Silicon that produces `linux/arm64` (native OpenCode; x86_64 `adb`/`aapt2` via qemu-user).

If `adb version` fails with a missing `/lib64/ld-linux-x86-64.so.2`, the arm64 image is missing its bundled x86_64 loader libs — rebuild with the current Dockerfile (it copies those libs from an amd64 stage).

## Persistence behavior

`opencode` is installed into the image at build time (`/usr/local/bin/opencode`), so you do **not** reinstall the binary each run.

State/config is persisted by default via a Docker named volume:

- Volume name: `opencode-home` when `CONTAINER_UID` is `10001`, otherwise `opencode-home-<uid>`
- Mounted at: `/home/opencode`

That means setup/auth files written under the container user's home directory should persist across runs.

Your project files are mounted from your host working directory into `/work`.

## Useful environment overrides

`run.sh` supports these optional env vars:

- `IMAGE_NAME` (default `opencode-sandbox:dev`)
- `IMAGE_NAME_PYTHON` (default `opencode-sandbox-python:dev`)
- `IMAGE_NAME_ANDROID` (default `opencode-sandbox-android:dev`)
- `IMAGE_NAME_OPENCODE` (optional override for non-python default name)
- `SANDBOX_ENV` (default `opencode`; supports `opencode`, `python`, `android`)
- `CONTAINER_NAME` (default `opencode-sandbox`)
- `STATE_VOLUME` (default `opencode-home` for uid 10001, otherwise `opencode-home-<uid>`)
- `STATE_INIT_MODE` (default `auto`; options `auto`, `volume`, `bind`)
- `STATE_BIND_DIR` (default `${HOME}/.local/share/opencode-sandbox/state`)
- `HOST_WORKDIR` (default current host directory)
- `MEMORY_LIMIT` (default `1g`)
- `CPU_LIMIT` (default `1.0`)
- `PIDS_LIMIT` (default `256`)
- `READ_ONLY_ROOTFS` (default `true`)
- `TMPFS_SIZE` (default `128m`)
- `RUN_TMPFS_SIZE` (default `64m`)
- `CONTAINER_UID` (default current host uid on Linux, `10001` on macOS)
- `CONTAINER_GID` (default current host gid on Linux, `10001` on macOS)
- `RUN_USER_TMPFS_SIZE` (default `32m`)
- `NETWORK_MODE` (default `bridge`)
- `SECCOMP_PROFILE` (default `seccomp/opencode-mac.json` on macOS)
- `SECCOMP_ENFORCE` (default `true` on macOS, `false` elsewhere)
- `APPARMOR_PROFILE` (default empty)
- `REQUIRE_APPARMOR` (default `false`)

Notes:
  - `APPARMOR_PROFILE` only applies when Docker host AppArmor is available. On macOS, the value is ignored with a warning.
  - `STATE_INIT_MODE=auto` tries `STATE_VOLUME` first, then falls back to `STATE_BIND_DIR` when writable checks fail.
  - `APPARMOR_PROFILE` + `REQUIRE_APPARMOR=true` switches to fail fast when AppArmor is unavailable.
  - On macOS, `SECCOMP_PROFILE` adds an additional hardening layer without requiring AppArmor.

`NETWORK_MODE` controls `docker run --network`; set `NETWORK_MODE=none` for strict offline mode.
`CONTAINER_UID` and `CONTAINER_GID` are passed through to `docker run --user`; on Linux this should be your host account to keep `/work` writable.
Common proxy env vars (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY` and lowercase variants) are also passed into the container for connector/network access.

Example:

```bash
MEMORY_LIMIT=2g CPU_LIMIT=2.0 ./run.sh
```

By default the container runs with a read-only root filesystem and writable mounts only for:

- `/work` (your host project directory)
- `/home/opencode` (persistent state)
- `/tmp`, `/run`, and `/run/user/<uid>` (in-memory tmpfs)
- `/tmp` is mounted with `exec` so OpenCode can initialize its terminal UI library
- `XDG_RUNTIME_DIR` is set to `/run/user/<uid>` in read-only mode
- `/run/user/<uid>` is mounted as that same uid/gid so the container user can create runtime sockets/files there

Disable read-only if needed:

```bash
READ_ONLY_ROOTFS=false ./run.sh
```

## Reset persisted opencode home state

If you need to start fresh, remove the named volume (default volume mode) or delete the bind directory (bind mode):

```bash
docker volume rm opencode-home            # default legacy UID 10001
docker volume rm "opencode-home-$(id -u)"  # host-uid-based default
rm -rf "$STATE_BIND_DIR"               # when using STATE_INIT_MODE=bind
```
