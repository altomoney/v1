#!/bin/bash

source "$(dirname "$0")/_loadEnv.sh"

forge script script/DeployMulticallTestnet.s.sol:DeployMulticallTestnet \
--rpc-url $RPC_URL \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv