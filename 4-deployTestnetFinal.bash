#!/bin/bash

. utils.bash

function 1-deployTapTokenPostLbp {
    echo -e "${GREEN}Deploying tap-token...\n${NC}"
    goToTapTokenAndGitSync
    
    set -x
    npx hardhat deploys final --network $main_chain $tag || printErrorHappened
    set +x

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