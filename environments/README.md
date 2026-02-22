## Environment Profiles

This sandbox supports build/runtime profiles via `SANDBOX_ENV`.

Current profiles:

- `opencode`
  - base `opencode` runtime
  - default image: `opencode-sandbox:dev`
- `python`
  - base `opencode` runtime plus Python toolchain (`python3`, `python3-pip`, `python3-venv`) and `uv`
  - default image: `opencode-sandbox-python:dev`

The Dockerfile now uses two named stages, `opencode` and `python`. `build.sh` selects `--target` from `SANDBOX_ENV` by default and requires `--sandbox-env` and `--target` to match when both are set.

The security model stays unchanged across profiles.

To add a new profile, keep profile selection in:

- `Dockerfile` (`base` stage for shared setup and per-profile stages)
- `build.sh` (`validate_sandbox_env`, profile image map, target wiring, `--sandbox-env`)
- `run.sh` (`validate_sandbox_env`, `--sandbox-env`, image defaults)
