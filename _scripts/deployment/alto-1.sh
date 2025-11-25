#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

FOUNDRY_PROFILE=deployment forge clean

FOUNDRY_PROFILE=deployment forge build

FOUNDRY_PROFILE=deployment forge script script/DeployAltoEthereumMainnet.s.sol:DeployAltoEthereumMainnetScript \
--rpc-url "https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}" \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv