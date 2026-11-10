// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";

/// @notice Concrete implementation of AltoOwnable2Step for testing purposes.
contract AltoOwnable2StepInstance is AltoOwnable2Step {
    constructor(address owner_) Ownable(owner_) {}
}

