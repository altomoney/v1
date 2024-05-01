#!/bin/bash

. utils.bash

function 1-deployTapTokenPostLbp {
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    goToTapToken
    
    npx hardhat deploys postLbp1 --network $main_chain $tag || printErrorHappened
    for chain in "${side_chains[@]}"
    do
        npx hardhat deploys postLbp1-sideChain --network $chain $tag || printErrorHappened
    done
    1-2-deployPeriphPostLbp # Needs to be called after tap-token postLbp1
    npx hardhat deploys postLbp2 --network $main_chain $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}

function 1-2-deployPeriphPostLbp {
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    goToPeriph

    npx hardhat deploys postLbp --network $main_chain $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}

function 2-deployTapiocaZPostLbp {
    echo -e "${GREEN}Deploying tapiocaz...\n${NC}"
    goToTapiocaz

    npx hardhat deploys postLbp --network $main_chain $tag || printErrorHappened
    for chain in "${side_chains[@]}"
    do
        npx hardhat deploys postLbp --network $chain $tag || printErrorHappened
    done

    exportAndPushCommit

    cd ../../
    printWd
}

function 3-deployTapiocaBarPostLbp {
    echo -e "${GREEN}Deploying tapioca-bar...\n${NC}"
    goToBar

    npx hardhat deploys postLbp --network $main_chain $tag || printErrorHappened
    for chain in "${side_chains[@]}"
    do
        npx hardhat deploys postLbp --network $chain $tag || printErrorHappened
    done
    npx hardhat deploys postLbp2 --network $main_chain $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}



function main {
    1-deployTapTokenPostLbp
    2-deployTapiocaZPostLbp
    3-deployTapiocaBarPostLbp
}

main