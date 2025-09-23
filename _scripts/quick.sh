#!/bin/bash

source "$(dirname "$0")/deployment/_loadEnv.sh"

forge script script/Quick.s.sol:SetMulticallOwner \
--rpc-url $RPC_URL \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv