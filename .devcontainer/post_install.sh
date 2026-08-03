#!/usr/bin/env bash

set -euo pipefail

# Install dependencies
eval "$(/home/vscode/.local/share/fnm/fnm env --shell bash)"
corepack pnpm install
