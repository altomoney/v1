#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

forge script script/DeployUniversalRewardsDistributorTestnet.s.sol:DeployUniversalRewardsDistributorTestnet \
--rpc-url $RPC_URL \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv