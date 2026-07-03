## Environment Profiles

This sandbox supports build/runtime profiles via `SANDBOX_ENV`.

Current profiles:

- `opencode`
  - base `opencode` runtime
  - default image: `opencode-sandbox:dev`
- `python`
  - base `opencode` runtime plus Python toolchain (`python3`, `python3-pip`, `python3-venv`) and `uv`
  - default image: `opencode-sandbox-python:dev`
- `android`
  - base `opencode` runtime plus Android SDK (JDK 17, `adb`, `sdkmanager`, Gradle-friendly env)
  - default image: `opencode-sandbox-android:dev`
  - relaxed runtime defaults: `READ_ONLY_ROOTFS=false`, higher memory/CPU limits
  - session bootstrap: `android-session-init.sh` runs before each command (connects host ADB in `host` mode, validates `/work`, then execs OpenCode or the requested command)
  - emulator modes via `ANDROID_EMULATOR_MODE`:
    - `host` (default): connect to emulator/device on the host via `adb connect`
    - `container` (opt-in): run emulator inside the container (Linux + KVM recommended)

The Dockerfile uses named stages: `opencode`, `python`, and `android`. `build.sh` selects `--target` from `SANDBOX_ENV` by default and requires `--sandbox-env` and `--target` to match when both are set.

The `opencode` and `python` profiles keep the same security model. The `android` profile relaxes some defaults (writable rootfs, higher limits) and offers a further-relaxed `container` emulator tier.

To add a new profile, keep profile selection in:

- `Dockerfile` (`base` stage for shared setup and per-profile stages)
- `build.sh` (`validate_sandbox_env`, profile image map, target wiring, `--sandbox-env`)
- `run.sh` (`validate_sandbox_env`, `--sandbox-env`, image defaults, profile-specific runtime flags)
