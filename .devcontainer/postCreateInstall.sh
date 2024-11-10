#!/bin/bash

# Install foundryup and forge
curl -L https://foundry.paradigm.xyz | bash
export PATH="$PATH:/home/vscode/.foundry/bin"
foundryup
forge --version

# Install lcov
sudo apt-get update
sudo apt-get -y install lcov
lcov --version

# Generate coverage report
forge coverage --ir-minimum --report lcov --no-match-coverage "(test|mock|node_modules|script|Fast)"

# Extract and generate HTML report
lcov --extract lcov.info --rc lcov_branch_coverage=1 --rc derive_function_end_line=0 -o lcov.info 'contracts/*' && genhtml lcov.info --rc branch_coverage=1 --rc derive_function_end_line=0 -o coverage
