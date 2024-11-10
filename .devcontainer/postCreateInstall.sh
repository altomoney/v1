#!/bin/bash

# Install foundryup and forge
curl -L https://foundry.paradigm.xyz | bash
export PATH="$PATH:/home/vscode/.foundry/bin"
foundryup
forge --version

# Install lcov
sudo apt-get update
sudo apt-get -y install lcov


