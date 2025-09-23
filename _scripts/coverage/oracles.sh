#!/bin/bash

# Coverage script for oracles contracts
echo "Generating coverage for oracles contracts..."

# Clean up previous coverage files
rm -rf lcov.info coverage

# Run coverage specifically for oracles contracts and tests
forge coverage \
  --match-path "test/oracles/*" \
  --ir-minimum \
  --allow-failure \
  --report lcov

# Wait for file generation
sleep 2

# Generate HTML report
genhtml ./lcov.info -o coverage --branch-coverage --rc derive_function_end_line=0 --ignore-errors inconsistent,corrupt

echo "Oracles coverage report generated in coverage/ directory"
echo "Open coverage/index.html in your browser to view the report"
