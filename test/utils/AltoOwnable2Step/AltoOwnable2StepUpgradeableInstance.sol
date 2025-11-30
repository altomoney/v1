// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";

/// @notice Concrete implementation of AltoOwnable2StepUpgradeable for testing purposes.
contract AltoOwnable2StepUpgradeableInstance is AltoOwnable2StepUpgradeable {
    function initialize(address owner_) external initializer {
        __Ownable_init(owner_);
        __Ownable2Step_init();
    }
}

