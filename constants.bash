#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


mainnet_main_chain="arbitrum"
mainnet_side_chains=("ethereum" "optimism")

testnet_main_chain="arbitrum_sepolia"
testnet_side_chains=("sepolia" "optimism_sepolia")


function printWd() {
    echo -e "${YELLOW}Navigated to: `pwd`${NC}"
}

function printErrorHappened() {
    echo -e "${RED}[-] An error occured. Exiting...${NC}"
    exit 1
}
