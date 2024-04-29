#!/bin/bash

. utils.bash


function 1-deployPeriphLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    goToPeriph

    npx hardhat deploys lbp --network $main_chain $tag || printErrorHappened
    exportAndPushCommit

    cd ../../
    printWd
}


function main {
    1-deployPeriphLbp
}

main