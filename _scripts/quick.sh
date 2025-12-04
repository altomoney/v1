#!/bin/bash

source "$(dirname "$0")/deployment/_loadEnv.sh"

forge script script/Quick.s.sol:SetApproveOnAdapter \
--rpc-url "https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_KEY}" \
--account $ACCOUNT \
--sender $SENDER \
--broadcast -vvv