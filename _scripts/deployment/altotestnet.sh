#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

FOUNDRY_PROFILE=testnet forge clean

FOUNDRY_PROFILE=testnet forge build

FOUNDRY_PROFILE=testnet forge script script/DeployAltoTestnet.s.sol:DeployAltoTestnetScript \
--rpc-url $RPC_URL \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv