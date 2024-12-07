// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerForceUnlockTest is TOBTestBase {
    address testUser;
    uint256 _lockAmount;
    uint256 _collateralAmount;
    uint256 _borrowAmount;

    function setUp() public override {
        super.setUp();
        testUser = makeAddr("testUser");
        _lockAmount = 1e18;
        _collateralAmount = 3e18;
        _borrowAmount = 1e18;
    }

    function _setupValidPosition() internal {
        _addCollateralBigBang(_collateralAmount, bigBangInstance, testUser, testUser, testUser, testUser, false);
        _borrowBigBang(_borrowAmount, bigBangInstance, testUser, testUser, testUser);
        tapToken.approve(address(tob), _lockAmount);
        usdo.approve(address(tob), _lockAmount);
        tob.lock(testUser, 0, _lockAmount, market);
    }

    function test_revertWhen_positionExpired() public {
        _setupValidPosition();

        // Advance time past lock duration
        vm.warp(block.timestamp + 1 weeks + 1);

        vm.startPrank(testUser);
        vm.expectRevert("PositionExpired()");
        tob.forceUnlock(0, testUser);
        vm.stopPrank();
    }

    function test_revertWhen_canStillLockWithDebt() public {
        _setupValidPosition();

        vm.startPrank(testUser);
        vm.expectRevert("CanStillLockWithDebt()");
        tob.forceUnlock(0, testUser);
        vm.stopPrank();
    }

    function test_forceUnlock_validConditions() public {
        _setupValidPosition();

        uint256 initialTotalUSDO = tob._totalLockedUsdo(testUser);
        int256 initialCurrentEpochDeposits = tob._netDepositsPerEpoch(block.timestamp);
        int256 initialExpiryEpochDeposits = tob._netDepositsPerEpoch(block.timestamp + 1 weeks);

        vm.startPrank(testUser);
        tob.forceUnlock(0, testUser);

        assertEq(tob._totalLockedUsdo(testUser), initialTotalUSDO - _lockAmount, "Total locked USDO should decrease");
        assertEq(
            tob._netDepositsPerEpoch(block.timestamp),
            initialCurrentEpochDeposits,
            "Current epoch deposits should not change"
        );
        assertEq(
            tob._netDepositsPerEpoch(block.timestamp + 1 weeks),
            initialExpiryEpochDeposits,
            "Expiry epoch deposits should not change"
        );

        vm.stopPrank();
    }
}
