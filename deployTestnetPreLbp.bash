#!/bin/bash

. utils.bash


function 1-deployPeriphPreLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    cd gitmodule/tapioca-periph
    printWd

    npx hardhat deploys preLbp --network $main_chain $tag
    exportAndPushCommit

    cd ../../
    printWd
}

function 2-deployTapTokenPreLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    cd gitmodule/tap-token
    printWd

    npx hardhat deploys preLbp --network $main_chain $tag
    exportAndPushCommit

    cd ../../
    printWd
}

function main {
    1-deployPeriphPreLbp
    2-deployTapTokenPreLbp
}

main