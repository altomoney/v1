#!/bin/bash

. constants.bash

if [ -z "$1" ]; then
    echo -e "${RED}Please provide a tag to deploy to.\n${NC}"
    exit 1
fi

# Give help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "${YELLOW}Usage: [TESTNET|MAINNET]=true ./deployTestnetPreLbp.bash <tag>\n${NC}"
    exit 0
fi


# Set the main chain and side chains
if [ "$TESTNET" = true ]; then
    main_chain=$testnet_main_chain
    side_chains=$testnet_side_chains
elif [ "$MAINNET" = true ]; then
    main_chain=$mainnet_main_chain
    side_chains=$mainnet_side_chains
else
    echo -e "${RED}Please set either TESTNET or MAINNET as env var to true.${NC}"
    echo -e "${RED}Example: TESTNET=true ./1-deployTestnetPreLbp.bash <tag>${NC}"
    exit 1
fi


tag="--tag $1"
SDK_BRANCH_NAME="tagged-deployments-$1"

# Functions

# Context needs to be inside of a repo
function exportAndPushCommit {
    if [ ! -f "foundry.toml" ]; then
        echo -e "${RED}Calling export outside of a project scope. Exiting...\n${NC}"
        exit 1
    fi
    
    # Export the deployments
    local currProject=${PWD##*/}
    echo -e "${GREEN}Exporting local deployments for ${currProject}...\n${NC}"
    npx hardhat sdk exportDep $tag
    echo -e "${GREEN}Local deployments exported!\n${NC}"

    cd gitmodule/tapioca-sdk
    printWd

    # Commit and push the changes
    echo -e "${GREEN}Committing and pushing changes...\n${NC}"
    git add src/global.db.json
    git commit -m "(\`${currProject}\`): Exported deployments on tag \`$SDK_BRANCH_NAME\`"
    git push --set-upstream origin $SDK_BRANCH_NAME
    echo -e "${GREEN}Changes committed and pushed!\n${NC}"

    # Navigate back to the root directory
    cd ../../
    printWd
}

function _goToModuleAndGitSync() {
    local module=$1
    echo -e "${GREEN}Navigating to $module...${NC}"
    cd gitmodule/$module || { echo -e "${RED}Failed to find $module. Exiting...${NC}"; exit 1; }
    
    # Make sure that the SDK branch is in sync the chosen tag 
    cd gitmodule/tapioca-sdk
    printWd


    # pull latest changes from SDK
    echo -e "${GREEN}Pulling SDK latest changes from $SDK_BRANCH_NAME...${NC}"

    git fetch origin
    if [ "$(git branch --show-current)" != "$SDK_BRANCH_NAME" ]; then
        # Check if the branch exists and checkout, if not create it and checkout
        git checkout --track origin/$SDK_BRANCH_NAME 2>/dev/null || git checkout -b $SDK_BRANCH_NAME
    fi
    git pull origin $SDK_BRANCH_NAME

    echo -e "${GREEN}Latest changes pulled!${NC}"

    cd ../../
    printWd
}

function goToTapTokenAndGitSync() {
    _goToModuleAndGitSync "tap-token"
}

function goToPeriphAndGitSync() {
    _goToModuleAndGitSync "tapioca-periph"
}

function goToYieldBoxAndGitSync() {
    _goToModuleAndGitSync "tap-yieldbox"
}

function goToBarAndGitSync() {
    _goToModuleAndGitSync "tapioca-bar"
}

function goToTapiocazAndGitSync() {
    _goToModuleAndGitSync "tapiocaz"
}