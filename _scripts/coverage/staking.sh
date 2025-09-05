#!/bin/bash

# Coverage script for staking contracts
echo "Generating coverage for staking contracts..."

# Clean up previous coverage files
rm -rf lcov.info coverage

# Run coverage specifically for staking contracts and tests
forge coverage \
  --match-path "test/staking/*" \
  --ir-minimum \
  --allow-failure \
  --report lcov

# Wait for file generation
sleep 2

# Generate HTML report
genhtml ./lcov.info -o coverage --branch-coverage --rc derive_function_end_line=0

echo "Staking coverage report generated in coverage/ directory"
echo "Open coverage/index.html in your browser to view the report"
