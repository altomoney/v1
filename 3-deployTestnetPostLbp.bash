#!/bin/bash

. utils.bash

if [ -z "$1" ]; then
    echo -e "${RED}Please provide a tag to deploy to.\n${NC}"
    exit 1
fi

# Give help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "${YELLOW}Usage: ./deployTestnetPreLbp.bash <tag>\n${NC}"
    exit 0
fi


function 1-deployTapTokenPostLbp {
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    goToTapToken
    
    npx hardhat deploys postLbp1 --network arbitrum_sepolia $tag || printErrorHappened
    npx hardhat deploys postLbp1-sideChain --network sepolia $tag || printErrorHappened
    1-2-deployPeriphPostLbp # Needs to be called after tap-token postLbp1
    npx hardhat deploys postLbp2 --network arbitrum_sepolia $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}

function 1-2-deployPeriphPostLbp {
    echo -e "${GREEN}Deploying tapioca-periph...\n${NC}"
    goToPeriph

    npx hardhat deploys postLbp --network arbitrum_sepolia $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}

function 2-deployTapiocaZPostLbp {
    echo -e "${GREEN}Deploying tapiocaz...\n${NC}"
    goToTapiocaz

    npx hardhat deploys postLbp --network arbitrum_sepolia $tag || printErrorHappened
    npx hardhat deploys postLbp --network sepolia $tag || printErrorHappened

    exportAndPushCommit

    cd ../../
    printWd
}

function 3-deployTapiocaBarPostLbp {
    echo -e "${GREEN}Deploying tapioca-bar...\n${NC}"
    goToBar

    npx hardhat deploys postLbp --network arbitrum_sepolia $tag || printErrorHappened
    npx hardhat deploys postLbp --network sepolia $tag || printErrorHappened
    npx hardhat deploys postLbp2 --network arbitrum_sepolia $tag || printErrorHappened

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