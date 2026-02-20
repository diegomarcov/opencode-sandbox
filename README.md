# Opencode Sandbox Container

This directory contains a hardened Docker image and a small launcher script for running `opencode` in a safer local-dev container.

## What is hardened right now (Phase 1)

- Container runs as non-root user `opencode` (uid `10001`)
- `no-new-privileges` is enabled
- All Linux capabilities are dropped (`--cap-drop=ALL`)
- Basic resource limits are enabled (`pids`, `memory`, `cpu`)
- Root filesystem can be read-only (`--read-only`) with writable tmpfs for `/tmp` and `/run`
- Optional AppArmor confinement is supported on Linux hosts via `APPARMOR_PROFILE`.

Networking is intentionally left enabled for now so flows like `/connect` can still work.

## Build

Build image:

```bash
./build.sh
```

`build.sh` reads default values from `build.env`, so the version and hashes are kept centralized.

`build.sh` auto-selects the container target platform from the host architecture:
- Linux x86_64 -> `linux/amd64`
- Linux arm64 / aarch64 -> `linux/arm64`
- macOS arm64 (Apple Silicon) -> `linux/arm64`

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

You can still pass a command when you need shell access or custom args:

```bash
./run.sh bash
```

```bash
./run.sh opencode --version
```

## Persistence behavior

`opencode` is installed into the image at build time (`/usr/local/bin/opencode`), so you do **not** reinstall the binary each run.

State/config is persisted by default via a Docker named volume:

- Volume name: `opencode-home`
- Mounted at: `/home/opencode`

That means setup/auth files written under the container user's home directory should persist across runs.

Your project files are mounted from your host working directory into `/work`.

## Useful environment overrides

`run.sh` supports these optional env vars:

- `IMAGE_NAME` (default `opencode-sandbox:dev`)
- `CONTAINER_NAME` (default `opencode-sandbox`)
- `STATE_VOLUME` (default `opencode-home`)
- `HOST_WORKDIR` (default current host directory)
- `MEMORY_LIMIT` (default `1g`)
- `CPU_LIMIT` (default `1.0`)
- `PIDS_LIMIT` (default `256`)
- `READ_ONLY_ROOTFS` (default `true`)
- `TMPFS_SIZE` (default `128m`)
- `RUN_TMPFS_SIZE` (default `64m`)
- `CONTAINER_UID` (default `10001`)
- `RUN_USER_TMPFS_SIZE` (default `32m`)
- `NETWORK_MODE` (default `bridge`)
- `APPARMOR_PROFILE` (default empty)
- `REQUIRE_APPARMOR` (default `false`)

Note: `APPARMOR_PROFILE` only applies when Docker host AppArmor is available. On macOS, the value is ignored with a warning.
`REQUIRE_APPARMOR=true` switches that behavior to fail fast instead of warning.
`NETWORK_MODE` controls `docker run --network`; set `NETWORK_MODE=none` for strict offline mode.

Example:

```bash
MEMORY_LIMIT=2g CPU_LIMIT=2.0 ./run.sh
```

By default the container runs with a read-only root filesystem and writable mounts only for:

- `/work` (your host project directory)
- `/home/opencode` (persistent state)
- `/tmp`, `/run`, and `/run/user/<uid>` (in-memory tmpfs)
- `/tmp` is mounted with `exec` so OpenCode can initialize its terminal UI library
- `XDG_RUNTIME_DIR` is set to `/run/user/10001` by default in read-only mode
- `/run/user/<uid>` is mounted as that same uid/gid so the container user can create runtime sockets/files there

Disable read-only if needed:

```bash
READ_ONLY_ROOTFS=false ./run.sh
```

## Reset persisted opencode home state

If you need to start fresh, remove the named volume:

```bash
docker volume rm opencode-home
```
