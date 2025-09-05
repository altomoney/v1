#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

forge script script/DeployAltoTestnet.s.sol:DeployAltoTestnetScript \
--rpc-url $RPC_URL \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv