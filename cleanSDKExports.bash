#!/bin/bash

. constants.bash
# List of submodules
submodules=("tap-token" "tap-yieldbox" "tapioca-bar" "tapioca-periph" "tapiocaz")

for module in "${submodules[@]}"
do
    echo -e "${GREEN}Cleaning $module...\n${NC}"
    cd gitmodule/$module/gitmodule/tapioca-sdk
    printWd
    git restore .
    echo -e "${GREEN}Cleaning $module done${NC}"

    cd ../../../../
    printWd
    echo -e "\n"
done

./init.bash