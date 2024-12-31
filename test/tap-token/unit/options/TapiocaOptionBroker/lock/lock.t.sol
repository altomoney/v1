// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase} from "../TOBTestBase.t.sol";

contract TapiocaOptionBrokerLockTest is TOBTestBase {
    address testUser;
    uint256 lockAmount;

    function setUp() public override {
        super.setUp();
        testUser = makeAddr("testUser");
        lockAmount = 1e18;
    }

    function _setupValidPosition(uint256 collateralAmount, uint256 borrowAmount) internal {
        _addCollateralBigBang(collateralAmount, bigBangInstance, testUser, testUser, testUser, testUser);
        _borrowBigBang(lockAmount, bigBangInstance, testUser, testUser, testUser);
    }

    function test_revertWhen_amountZero() public {
        vm.startPrank(testUser);
        vm.expectRevert("NotValid()");
        tob.lock(testUser, 0, 0, market);
        vm.stopPrank();
    }

    function test_revertWhen_marketNotActive() public {
        address inactiveMarket = makeAddr("inactiveMarket");
        vm.startPrank(testUser);
        vm.expectRevert("NotValid()");
        tob.lock(testUser, 0, lockAmount, inactiveMarket);
        vm.stopPrank();
    }

    function test_revertWhen_paused() public {
        vm.startPrank(owner);
        tob.setPause(true);
        vm.stopPrank();

        vm.startPrank(testUser);
        vm.expectRevert("Paused()");
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_revertWhen_emergencySweepActive() public {
        vm.startPrank(owner);
        tob.setEmergencySweepCooldown(0);
        vm.warp(block.timestamp + 1 days);
        tob.emergencySweep(address(tapToken));
        vm.stopPrank();

        vm.startPrank(testUser);
        vm.expectRevert("EmergencySweepActive()");
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_lock_validConditions() public {
        _setupValidPosition(3e18, lockAmount);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount);

        uint256 initialTotalUSDO = tob._totalLockedUsdo(testUser);
        int256 initialCurrentEpochDeposits = tob._netDepositsPerEpoch(block.timestamp);
        int256 initialExpiryEpochDeposits = tob._netDepositsPerEpoch(block.timestamp + 1 weeks);

        tob.lock(testUser, 0, lockAmount, market);

        assertEq(tob._totalLockedUsdo(testUser), initialTotalUSDO + lockAmount, "Total locked USDO should increase");
        assertEq(
            tob._netDepositsPerEpoch(block.timestamp),
            initialCurrentEpochDeposits + int256(lockAmount),
            "Current epoch deposits should increase"
        );
        assertEq(
            tob._netDepositsPerEpoch(block.timestamp + 1 weeks),
            initialExpiryEpochDeposits - int256(lockAmount),
            "Expiry epoch deposits should decrease"
        );

        vm.stopPrank();
    }

    function test_lock_withExistingPosition_notExpired() public {
        _setupValidPosition(3e18, lockAmount);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        // First lock
        tob.lock(testUser, 0, lockAmount, market);

        // Second lock should fail
        vm.expectRevert("PositionNotExpired()");
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_lock_withExistingPosition_expired() public {
        _mintTapToken(testUser, lockAmount * 2);

        // Mock market's addAsset function
        vm.mockCall(
            market,
            abi.encodeWithSignature(
                "addAsset(address,address,bool,uint256)", address(tob), address(tob), false, lockAmount
            ),
            abi.encode(lockAmount)
        );

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        // First lock
        tob.lock(testUser, 0, lockAmount, market);

        // Advance time past lock duration
        vm.warp(block.timestamp + 1 weeks + 1);

        // Second lock should succeed
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }
}
