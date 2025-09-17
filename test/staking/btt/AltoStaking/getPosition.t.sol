// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {StakingPosition} from "@alto/staking/interfaces/IAltoStaking.sol";

contract AltoStaking_GetPosition_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    // Test: when position does not exist -> it should return empty position
    function test_GetPosition_WhenPositionDoesNotExist() public {
        StakingPosition memory position = staking.getPosition(USER, CONTAINER_ID);

        _assertPositionEmpty(position);
    }

    // Test: when position exists -> it should return position data
    function test_GetPosition_WhenPositionExists() public {
        uint256 lockAmount = LOCK_AMOUNT;

        // Create a position
        _lockPosition(USER, lockAmount, CONTAINER_ID, false);

        StakingPosition memory position = staking.getPosition(USER, CONTAINER_ID);

        assertEq(position.amountLocked, lockAmount);
        assertEq(position.lockedTimestamp, block.timestamp);
        assertGt(position.expiryTimestamp, block.timestamp);
    }
}
