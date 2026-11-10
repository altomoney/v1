#!/bin/bash

source "$(dirname "$0")/load-env.sh"

FOUNDRY_PROFILE=deployment forge clean

FOUNDRY_PROFILE=deployment forge build

FOUNDRY_PROFILE=deployment forge script --ffi script/DeployAltoEthereumMainnet.s.sol:DeployAltoEthereumMainnetScript \
--rpc-url "https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}" \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv \
--slow \
--with-gas-price 0.6gwei --priority-gas-price 0.2gwei