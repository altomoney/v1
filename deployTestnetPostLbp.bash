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
    # Start with tap token
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    cd gitmodule/tap-token
    printWd
    
    npx hardhat deploys preLbp --network arbitrum_sepolia $tag
    exportAndPushCommit 

    cd ../../
    printWd
}

function main {
    1-deployTapTokenPostLbp
}

main