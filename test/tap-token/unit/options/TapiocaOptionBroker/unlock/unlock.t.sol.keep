// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";
import {ITapiocaOptionBroker} from "tap-token/interfaces/ITapiocaOptionBroker.sol";
import "forge-std/console.sol";

contract TapiocaOptionBrokerUnlockTest is TOBTestBase {
    uint8 bucketId;
    uint256 lockAmount;
    uint256 lockDuration;
    uint256 collateralAmount;

    function setUp() public override {
        super.setUp();

        bucketId = 0;
        lockAmount = 100000e18;
        lockDuration = 1 weeks;
        collateralAmount = 300000e18;
    }

    function _setupValidPosition(address user) internal {
        _addCollateralBigBang(collateralAmount, bigBangInstance, user, user, user, user);
        _borrowBigBang(lockAmount, bigBangInstance, user, user, user);

        console.log("user balance", usdo.balanceOf(user));
        vm.startPrank(user);
        usdo.approve(address(tob), lockAmount);
        tob.lock(user, bucketId, lockAmount, address(market));
        vm.stopPrank();
    }

    function test_revertWhen_positionNotExpired() public {
        _setupValidPosition(user1);

        vm.expectRevert(ITapiocaOptionBroker.LockNotExpired.selector);

        vm.startPrank(user1);
        tob.unlock(bucketId, user1);
        vm.stopPrank();
    }

    function test_unlock_validConditions() public {
        _setupValidPosition(user1);

        // Store initial values
        uint256 initialTotalUSDO = tob._totalLockedUsdo(user1);
        int256 initialCurrentEpochDeposits = tob._netDepositsPerEpoch(block.timestamp);
        int256 initialExpiryEpochDeposits = tob._netDepositsPerEpoch(block.timestamp + lockDuration);

        uint256 blockTimestamp = block.timestamp;

        // Advance time past lock duration
        vm.warp(block.timestamp + (lockDuration * 10) + 1);

        vm.startPrank(user1);
        tob.unlock(bucketId, user1);

        // Verify position is cleared
        assertEq(tob._totalLockedUsdo(user1), initialTotalUSDO - lockAmount, "Total USDO should be updated");

        // Verify net deposits remain unchanged
        assertEq(
            tob._netDepositsPerEpoch(blockTimestamp),
            initialCurrentEpochDeposits,
            "Current epoch deposits should not change"
        );
        assertEq(
            tob._netDepositsPerEpoch(blockTimestamp + lockDuration),
            initialExpiryEpochDeposits,
            "Expiry epoch deposits should not change"
        );

        vm.stopPrank();
    }
}
