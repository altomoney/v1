
if [ -z "$1" ]; then
    echo -e "${RED}Please provide a tag to deploy to.\n${NC}"
    exit 1
fi

# Give help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo -e "${YELLOW}Usage: ./deployTestnetPreLbp.bash <tag>\n${NC}"
    exit 0
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
    echo -e "${GREEN}Exporting local deployments...\n${NC}"
    npx hardhat sdk exportDep $tag
    echo -e "${GREEN}Local deployments exported!\n${NC}"

    cd gitmodule/tapioca-sdk
    printWd

    # Commit and push the changes
    echo -e "${GREEN}Committing and pushing changes...\n${NC}"
    # Check if current branch is $SDK_BRANCH_NAME, if not checkout to it
    if [ "$(git branch --show-current)" != "$SDK_BRANCH_NAME" ]; then
        # Check if the branch exists and checkout, if not create it and checkout
        git checkout $SDK_BRANCH_NAME 2>/dev/null || git checkout -b $SDK_BRANCH_NAME
    fi
    git add src/global.db.json
    git commit -m "(\`${PWD##*/}\`): Exported deployments on $tag"
    git push --set-upstream origin $SDK_BRANCH_NAME
    echo -e "${GREEN}Changes committed and pushed!\n${NC}"

    # Navigate back to the root directory
    cd ../../
    printWd
}