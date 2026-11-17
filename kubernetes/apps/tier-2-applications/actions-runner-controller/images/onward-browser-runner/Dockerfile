# Keep this base pin and runners/onward/helmrelease.yaml's image pin together.
FROM ghcr.io/home-operations/actions-runner:2.338.2@sha256:2dd7caa094a425c041539447cb0e6ae63cda10b5242773764683b695b8fa5613

USER root
RUN set -eu; \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    cd /tmp; \
    curl --fail --show-error --location --retry 3 \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
      -o google-chrome.deb; \
    apt-get install -y --no-install-recommends ./google-chrome.deb \
      fonts-liberation fonts-noto-color-emoji; \
    /opt/google/chrome/chrome --version; \
    ldd /opt/google/chrome/chrome > /tmp/chrome-libraries; \
    if grep 'not found' /tmp/chrome-libraries; then \
      echo 'Chrome has unresolved libraries' >&2; exit 1; \
    fi; \
    rm -f /tmp/google-chrome.deb /tmp/chrome-libraries; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ARG CHROME_VERSION=unknown
LABEL org.opencontainers.image.source="https://github.com/sulibot/home-ops" \
      org.opencontainers.image.description="Onward Full gate runner with Google Chrome Stable and fonts" \
      org.opencontainers.image.base.name="ghcr.io/home-operations/actions-runner:2.338.2@sha256:2dd7caa094a425c041539447cb0e6ae63cda10b5242773764683b695b8fa5613" \
      com.google.chrome.version="${CHROME_VERSION}"

USER runner
