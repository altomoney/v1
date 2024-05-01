#!/bin/bash

. utils.bash

function 1-deployPeriphPreLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    cd gitmodule/tapioca-periph
    printWd

    npx hardhat deploys preLbp --network $main_chain $tag || printErrorHappened
    for chain in "${side_chains[@]}"
    do
        npx hardhat deploys preLbp --network $chain $tag || printErrorHappened
    done
    exportAndPushCommit

    cd ../../
    printWd
}

function 2-deployTapTokenPreLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    goToTapToken

    npx hardhat deploys preLbp --network $main_chain $tag || printErrorHappened
    exportAndPushCommit

    cd ../../
    printWd
}

function 3-deployYieldBoxPreLbp {
    # Start with tap token
    echo -e "${GREEN}Deploying tap-yieldbox...\n${NC}"
    goToYieldBox

    npx hardhat deploys yieldBox --network $main_chain $tag || printErrorHappened
    for chain in "${side_chains[@]}"
    do
        npx hardhat deploys preLbp --network $chain $tag || printErrorHappened
    done
    exportAndPushCommit

    cd ../../
    printWd
}

function main {
    1-deployPeriphPreLbp
    2-deployTapTokenPreLbp
    3-deployYieldBoxPreLbp
}

main