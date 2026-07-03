FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9 AS base

ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_X64_BASELINE
ARG OPENCODE_SHA256_ARM64
ARG OPENCODE_GITHUB_REPO
ARG OPENCODE_TARGETPLATFORM
ARG SANDBOX_ENV=opencode

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -euo pipefail; \
    if [ "${SANDBOX_ENV}" != "opencode" ] && [ "${SANDBOX_ENV}" != "python" ] && [ "${SANDBOX_ENV}" != "android" ]; then \
      echo "Unsupported SANDBOX_ENV: ${SANDBOX_ENV}" >&2; \
      echo "Supported values: opencode, python, android" >&2; \
      exit 1; \
    fi; \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates curl git tar \
    && rm -rf /var/lib/apt/lists/*

COPY build.env /tmp/build.env

RUN set -euo pipefail; \
    ARG_OPENCODE_VERSION="${OPENCODE_VERSION-}"; \
    ARG_OPENCODE_SHA256_X64_BASELINE="${OPENCODE_SHA256_X64_BASELINE-}"; \
    ARG_OPENCODE_SHA256_ARM64="${OPENCODE_SHA256_ARM64-}"; \
    ARG_OPENCODE_GITHUB_REPO="${OPENCODE_GITHUB_REPO-}"; \
    ARG_OPENCODE_TARGETPLATFORM="${OPENCODE_TARGETPLATFORM-}"; \
    . /tmp/build.env; \
    OPENCODE_VERSION="${ARG_OPENCODE_VERSION:-${OPENCODE_VERSION}}"; \
    OPENCODE_SHA256_X64_BASELINE="${ARG_OPENCODE_SHA256_X64_BASELINE:-${OPENCODE_SHA256_X64_BASELINE}}"; \
    OPENCODE_SHA256_ARM64="${ARG_OPENCODE_SHA256_ARM64:-${OPENCODE_SHA256_ARM64}}"; \
    OPENCODE_GITHUB_REPO="${ARG_OPENCODE_GITHUB_REPO:-${OPENCODE_GITHUB_REPO}}"; \
    OPENCODE_TARGETPLATFORM="${ARG_OPENCODE_TARGETPLATFORM:-${OPENCODE_TARGETPLATFORM:-linux/amd64}}"; \
    if [ -z "$OPENCODE_VERSION" ]; then echo "Missing OPENCODE_VERSION"; exit 1; fi; \
    if [ -z "$OPENCODE_SHA256_X64_BASELINE" ]; then echo "Missing OPENCODE_SHA256_X64_BASELINE"; exit 1; fi; \
    if [ -z "$OPENCODE_SHA256_ARM64" ]; then echo "Missing OPENCODE_SHA256_ARM64"; exit 1; fi; \
    if [ -z "$OPENCODE_GITHUB_REPO" ]; then echo "Missing OPENCODE_GITHUB_REPO"; exit 1; fi; \
    rm -f /tmp/build.env; \
    case "${OPENCODE_TARGETPLATFORM}" in \
      */amd64|amd64) \
        artifact="opencode-linux-x64-baseline.tar.gz"; \
        expected_sha256="$OPENCODE_SHA256_X64_BASELINE"; \
        ;; \
      */arm64|arm64|aarch64) \
        artifact="opencode-linux-arm64.tar.gz"; \
        expected_sha256="$OPENCODE_SHA256_ARM64"; \
        ;; \
      *) \
        echo "Unsupported target platform: ${OPENCODE_TARGETPLATFORM}"; \
        echo "Supported target platforms: linux/amd64 and linux/arm64"; \
        exit 1; \
        ;; \
    esac; \
    url="https://github.com/${OPENCODE_GITHUB_REPO}/releases/download/v${OPENCODE_VERSION}/${artifact}"; \
    archive="/tmp/opencode-${artifact}"; \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o "$archive" "$url"; \
    printf "%s  %s\n" "$expected_sha256" "$archive" | sha256sum -c -; \
    tar -xzf "$archive" -C /tmp; \
    install -m 0755 /tmp/opencode /usr/local/bin/opencode; \
    rm -rf /tmp/opencode "$archive"; \
    opencode --version

# Create unprivileged runtime user and writable directories.
RUN useradd --create-home --uid 10001 --shell /bin/bash opencode \
 && install -d -m 0750 -o opencode -g opencode /work

ENV HOME=/home/opencode
USER opencode:opencode

WORKDIR /work
CMD ["bash"]

FROM base AS opencode

FROM base AS python

USER root

RUN set -euo pipefail; \
    mkdir -p /var/lib/apt/lists/partial \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       python3 python3-pip python3-venv \
    && python3 -m pip install --no-cache-dir --break-system-packages uv \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && rm -rf /var/lib/apt/lists/*

RUN python3 --version >/dev/null \
    && uv --version >/dev/null

USER opencode:opencode

FROM base AS android

ARG OPENCODE_TARGETPLATFORM
ARG ANDROID_SDK_VERSION
ARG ANDROID_BUILD_TOOLS
ARG ANDROID_PLATFORM
ARG ANDROID_EMULATOR_IMAGE_AMD64
ARG ANDROID_EMULATOR_IMAGE_ARM64
ARG ANDROID_INSTALL_EMULATOR=false

USER root

RUN set -euo pipefail; \
    mkdir -p /var/lib/apt/lists/partial \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openjdk-17-jdk-headless unzip wget \
       libgl1 libpulse0 libx11-6 libxcb1 libnss3 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

COPY build.env /tmp/build.env

RUN set -euo pipefail; \
    ARG_OPENCODE_TARGETPLATFORM="${OPENCODE_TARGETPLATFORM-}"; \
    ARG_ANDROID_SDK_VERSION="${ANDROID_SDK_VERSION-}"; \
    ARG_ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS-}"; \
    ARG_ANDROID_PLATFORM="${ANDROID_PLATFORM-}"; \
    ARG_ANDROID_EMULATOR_IMAGE_AMD64="${ANDROID_EMULATOR_IMAGE_AMD64-}"; \
    ARG_ANDROID_EMULATOR_IMAGE_ARM64="${ANDROID_EMULATOR_IMAGE_ARM64-}"; \
    ARG_ANDROID_INSTALL_EMULATOR="${ANDROID_INSTALL_EMULATOR-}"; \
    . /tmp/build.env; \
    OPENCODE_TARGETPLATFORM="${ARG_OPENCODE_TARGETPLATFORM:-${OPENCODE_TARGETPLATFORM:-linux/amd64}}"; \
    ANDROID_SDK_VERSION="${ARG_ANDROID_SDK_VERSION:-${ANDROID_SDK_VERSION}}"; \
    ANDROID_BUILD_TOOLS="${ARG_ANDROID_BUILD_TOOLS:-${ANDROID_BUILD_TOOLS}}"; \
    ANDROID_PLATFORM="${ARG_ANDROID_PLATFORM:-${ANDROID_PLATFORM}}"; \
    ANDROID_EMULATOR_IMAGE_AMD64="${ARG_ANDROID_EMULATOR_IMAGE_AMD64:-${ANDROID_EMULATOR_IMAGE_AMD64}}"; \
    ANDROID_EMULATOR_IMAGE_ARM64="${ARG_ANDROID_EMULATOR_IMAGE_ARM64:-${ANDROID_EMULATOR_IMAGE_ARM64}}"; \
    ANDROID_INSTALL_EMULATOR="${ARG_ANDROID_INSTALL_EMULATOR:-${ANDROID_INSTALL_EMULATOR:-false}}"; \
    rm -f /tmp/build.env; \
    case "${OPENCODE_TARGETPLATFORM}" in \
      */amd64|amd64) \
        ANDROID_EMULATOR_IMAGE="${ANDROID_EMULATOR_IMAGE_AMD64}"; \
        ;; \
      */arm64|arm64|aarch64) \
        ANDROID_EMULATOR_IMAGE="${ANDROID_EMULATOR_IMAGE_ARM64}"; \
        ;; \
      *) \
        echo "Unsupported target platform for android profile: ${OPENCODE_TARGETPLATFORM}"; \
        exit 1; \
        ;; \
    esac; \
    ANDROID_HOME="/opt/android-sdk"; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    cmdline_archive="commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip"; \
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      -o "/tmp/${cmdline_archive}" \
      "https://dl.google.com/android/repository/${cmdline_archive}"; \
    unzip -q "/tmp/${cmdline_archive}" -d "${ANDROID_HOME}/cmdline-tools"; \
    rm -f "/tmp/${cmdline_archive}"; \
    mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"; \
    export ANDROID_HOME ANDROID_SDK_ROOT="${ANDROID_HOME}"; \
    export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}"; \
    yes | sdkmanager --licenses >/dev/null 2>&1 || test $? -eq 141; \
    sdkmanager \
      "platform-tools" \
      "platforms;${ANDROID_PLATFORM}" \
      "build-tools;${ANDROID_BUILD_TOOLS}"; \
    if [ "$(echo "${ANDROID_INSTALL_EMULATOR}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then \
      sdkmanager "emulator" "${ANDROID_EMULATOR_IMAGE}"; \
    fi; \
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"; \
    ln -sfn "${JAVA_HOME}" /usr/lib/jvm/default-java-17; \
    chown -R opencode:opencode "${ANDROID_HOME}"; \
    install -d -m 0750 -o opencode -g opencode /home/opencode/.android /home/opencode/.gradle

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH="/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/emulator:${PATH}"
ENV JAVA_HOME=/usr/lib/jvm/default-java-17
ENV GRADLE_USER_HOME=/home/opencode/.gradle

COPY scripts/android-connect-host-core.sh scripts/android-connect-host.sh scripts/android-session-init.sh scripts/android-avd-init.sh scripts/android-emulator-start.sh /usr/local/bin/
COPY resources/android/AGENTS.md /usr/share/opencode-sandbox/android/AGENTS.md
RUN chmod +x /usr/local/bin/android-connect-host-core.sh /usr/local/bin/android-connect-host.sh /usr/local/bin/android-session-init.sh /usr/local/bin/android-avd-init.sh /usr/local/bin/android-emulator-start.sh

USER opencode:opencode

FROM opencode
