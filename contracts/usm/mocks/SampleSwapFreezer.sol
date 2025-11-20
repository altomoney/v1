// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUsm} from "../interfaces/IUsm.sol";

/**
 * @title SampleSwapFreezer
 * @author Aave
 * @notice Minimal Swap Freezer that can serve as sample contract
 */
contract SampleSwapFreezer is Ownable {
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Triggers freezing of a USM
     * @param usm Address of the USM
     */
    function triggerFreeze(address usm) external onlyOwner {
        IUsm(usm).setSwapFreeze(true);
    }

    /**
     * @notice Triggers unfreezing of a USM
     * @param usm Address of the USM
     */
    function triggerUnfreeze(address usm) external onlyOwner {
        IUsm(usm).setSwapFreeze(false);
    }
}
