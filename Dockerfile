FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9

ARG OPENCODE_VERSION
ARG OPENCODE_SHA256_X64_BASELINE
ARG OPENCODE_SHA256_ARM64
ARG OPENCODE_GITHUB_REPO
ARG OPENCODE_TARGETPLATFORM

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
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
