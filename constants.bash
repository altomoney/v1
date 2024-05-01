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

function _goToModule() {
    local module=$1
    echo -e "${GREEN}Navigating to $module...${NC}"
    cd gitmodule/$module || { echo -e "${RED}Failed to find $module. Exiting...${NC}"; exit 1; }
    printWd
}

function goToTapToken() {
    _goToModule "tap-token"
}

function goToPeriph() {
    _goToModule "tapioca-periph"
}

function goToYieldBox() {
    _goToModule "tap-yieldbox"
}

function goToBar() {
    _goToModule "tapioca-bar"
}

function goToTapiocaz() {
    _goToModule "tapiocaz"
}