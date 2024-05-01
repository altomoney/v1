#!/bin/bash

. constants.bash

# List of submodules
submodules=("tap-token" "tap-yieldbox" "tapioca-bar" "tapioca-periph" "tapiocaz")

# Corresponding branches for each submodule
branches=(
    "dev"  # tap-token
    "main"                            # tap-yieldbox
    "pre-prod-deployment-scripts"     # tapioca-bar
    "dev"    # tapioca-periph
    "pre-prod-deployment-scripts"              # tapiocaz
)


function initializeGit {
    # Init and update the git submodules
    echo -e "${GREEN}[+] Initializing cores submodules\n${NC}"
    git submodule update --init

    # Navigate to the gitmodule directory
    echo -e "${YELLOW}Navigating to the gitmodule directory...\n${NC}"
    cd gitmodule || { echo -e "${RED}Failed to find the gitmodule directory. Exiting...\n${NC}"; exit 1; }

    echo -e "${YELLOW}Initializing and setting branches for submodules...\n${NC}"
    # Initialize each submodule and set to the specific branch
    for i in "${!submodules[@]}"; do
        local submodule="${submodules[$i]}"
        local branch="${branches[$i]}"
        
        echo -e "${GREEN}Processing $submodule...\n${NC}"
        git submodule update --init "$submodule"
        cd "$submodule" || { echo -e "${RED}Failed to navigate into $submodule. Skipping...\n${NC}"; continue; }
        printWd
        git fetch origin "$branch"
        git checkout "$branch"
        git pull origin "$branch"
        echo -e "${GREEN}Set $submodule to branch $branch.\n${NC}"

        # Initialize lib/forge-std
        echo -e "${YELLOW}Initializing submodule forge-std...\n${NC}"
        git submodule update --init lib/forge-std

        # Now handle each submodule of this submodule
        local submodule_list=`ls gitmodule`

        # Context is now 2 level deep, in the submodule directory (gitmodule/submodule)
        for nested_submodule in $submodule_list; do
            local submodule_access="gitmodule/$nested_submodule"
            echo -e "\t${YELLOW}Initializing submodule $nested_submodule of $submodule...\n${NC}"
            git submodule update --init "$submodule_access"

            # Determine the branch of the nested submodule
            local nested_branch="main" # Default to main if no specific branch is defined
            for j in "${!submodules[@]}"; do
                # Transform to lowercase for comparison
                if [ "${submodules[$j]}" = `echo $nested_submodule | tr '[:upper:]' '[:lower:]'` ]; then
                    nested_branch="${branches[$j]}"
                    break
                fi
            done
            echo -e "\t${GREEN}Processing $submodule / $nested_submodule...\n${NC}"
            cd "${submodule_access}" # Navigate to the nested submodule, context 4 levels deep (gitmodule/submodule/gitmodule/nested_submodule)
            printWd
            git fetch origin "$nested_branch"
            git checkout "$nested_branch"
            git pull origin "$nested_branch"
            echo -e "\t${GREEN}Set $submodule / $nested_submodule to branch $nested_branch.\n${NC}"

            # Special condition to check if the submodule is tapioca-periph, and it has a nested submodule inside gitmodule named permitc
            # if that's the case, we init and set the branch for permitc
            # This is happens because PermitC insode tapioca-periph is used in tap-token and tapiocaz
            if [ "$nested_submodule" = "tapioca-periph" ]; then
                echo -e "\t${YELLOW}Initializing submodule permitc of tapioca-periph...\n${NC}"
                git submodule update --init gitmodule/permitc
            fi

            # Navigate back to the submodule directory
            cd ../../
            printWd

        done
        cd .. # Navigate back to the gitmodule directory
        printWd
    done
    cd .. # Navigate back to the root directory
    printWd
}

function yarnInstallAndSetup {
    echo -e "${YELLOW}Installing Node.js dependencies where applicable...\n${NC}"
    cd gitmodule || { echo -e "${RED}Failed to find the gitmodule directory. Exiting...\n${NC}"; exit 1; }
    printWd

    # Install Node dependencies for all submodules listed
    for submodule in "${submodules[@]}"; do
        echo -e "${GREEN}Copying .env folder into $submodule\n${NC}"
        cp -r ../.env "$submodule"

        echo -e "${GREEN}Installing dependencies for $submodule...\n${NC}"
        cd "$submodule" || { echo -e "${RED}Failed to navigate into $submodule. Skipping dependency installation...\n${NC}"; continue; }
        printWd

        yarn install
        echo -e "${GREEN}Dependencies installed for $submodule.\n${NC}"
        
        # Compiling hardhat
        echo -e "${GREEN}Running hardhat compile $submodule...\n${NC}"
        npx hardhat compile

        cd .. # Navigate back to the gitmodule directory
        printWd
    done
    cd ..  # Navigate back to the root directory
    printWd
}

function main {
    initializeGit
    echo -e "${GREEN}🎉🎉🎉 Git submodules initialized! 🎉🎉🎉\n${NC}"
    yarnInstallAndSetup
    echo -e "${GREEN}🎉🎉🎉 Protocols initalized! 🎉🎉🎉\n${NC}"
}

main
