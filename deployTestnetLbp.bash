#!/bin/bash

. utils.bash


function 1-deployPeriphLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    cd gitmodule/tapioca-periph
    printWd

    npx hardhat deploys lbp --network $main_chain $tag || { echo -e "${RED}[-] An error occured. Exiting...\n${NC}" ; exit 1; }
    exportAndPushCommit

    cd ../../
    printWd
}


function main {
    1-deployPeriphLbp
}

main