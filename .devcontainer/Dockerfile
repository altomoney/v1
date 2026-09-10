FROM mcr.microsoft.com/devcontainers/base:bookworm

ARG MISE_VERSION=2026.9.4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends lcov \
    && rm -rf /var/lib/apt/lists/*

USER vscode

ENV DEVCONTAINER=true
ENV PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:${PATH}"

RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" sh
