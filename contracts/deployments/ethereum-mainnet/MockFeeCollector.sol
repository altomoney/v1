// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AltoOwnable2Step} from "@alto/utils/AltoOwnable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Mock fee collector contract - placeholder until actual fee collector is implemented
contract MockFeeCollector is AltoOwnable2Step {
    constructor(address _owner, address _feeRecipient) Ownable(_owner) {}
}
