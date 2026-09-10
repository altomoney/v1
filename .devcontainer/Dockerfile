FROM mcr.microsoft.com/vscode/devcontainers/base:debian

ARG FOUNDRY_VERSION=1.7.1

# Update package list
RUN apt update
# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Install dependencies
RUN apt install -y lcov

###### user running scripts ######
USER vscode

# Install foundry suite
RUN curl -L https://foundry.paradigm.xyz | ENV="$HOME/.bashrc" SHELL="$(which bash)" bash -
RUN /home/vscode/.foundry/bin/foundryup --install "${FOUNDRY_VERSION}"

# Install FNM
RUN curl -o- https://fnm.vercel.app/install | ENV="$HOME/.bashrc" SHELL="$(which bash)" bash -
# Install Node.js
RUN /home/vscode/.local/share/fnm/fnm install 22
# Install yarn and graphite CLI
RUN eval "$(/home/vscode/.local/share/fnm/fnm env --use-on-cd)" && npm install -g yarn && npm install -g @withgraphite/graphite-cli@stable

# Switch back to root user
USER root
