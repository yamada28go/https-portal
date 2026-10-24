# Development only: preserve the project's Ruby baseline.
FROM node:22.14.0-bullseye-slim@sha256:73a9dfbb6c761aebdf4666cce2627635a30d1d4c20f67ff642d01b8f09e709a3 AS node
FROM ruby:2.7.2-buster@sha256:1dd0106849233fcd913b7c4608078fa1a53a5e3ce1af2a55e4d726b0d8868e2f

ARG CODEX_VERSION=0.164.0
# Buster moved to the signed Debian archive. Keep signature/TLS verification.
RUN printf '%s\n' \
      'deb http://archive.debian.org/debian buster main' \
      'deb http://archive.debian.org/debian-security buster/updates main' \
      > /etc/apt/sources.list \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install -y --no-install-recommends ca-certificates git ripgrep libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force \
    && gem install bundler --version 2.2.4 --no-document \
    && ruby --version && node --version && codex --version \
    && bundle _2.2.4_ --version

RUN groupadd --gid 1000 dev \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash dev \
    && mkdir -p /workspace /bundle /home/dev/.codex \
    && chown dev:dev /workspace /bundle /home/dev/.codex
COPY entrypoint.sh /usr/local/bin/dev-entrypoint
COPY versions.sh /usr/local/bin/dev-versions
COPY codex-dev.sh /usr/local/bin/codex-dev
RUN chmod 755 /usr/local/bin/dev-entrypoint /usr/local/bin/dev-versions /usr/local/bin/codex-dev
ENV HOME=/home/dev \
    CODEX_HOME=/home/dev/.codex \
    BUNDLE_PATH=/bundle \
    BUNDLE_APP_CONFIG=/tmp/https-portal-bundle-config \
    BUNDLE_IGNORE_CONFIG=1 \
    SKIP_BUILD=1 \
    LANG=C.UTF-8
USER dev
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/dev-entrypoint"]
CMD ["sleep", "infinity"]
