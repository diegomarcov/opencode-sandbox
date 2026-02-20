FROM ubuntu:24.04
SHELL ["/bin/bash", "-lc"]
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://opencode.ai/install | bash

# Put opencode on PATH for runtime
RUN set -euo pipefail; \
    found=""; \
    for p in /root/.local/bin/opencode /root/.opencode/bin/opencode /root/.local/share/opencode/bin/opencode; do \
      if [ -x "$p" ]; then found="$p"; break; fi; \
    done; \
    test -n "$found"; \
    install -m 0755 "$found" /usr/local/bin/opencode; \
    opencode --version

WORKDIR /work
CMD ["bash"]