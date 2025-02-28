// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TOBTestBase, ITapiocaOptionBroker} from "../TOBTestBase.t.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {Participation, Bucket} from "tap-token/interfaces/ITapiocaOptionBroker.sol";

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
        _borrowBigBang(borrowAmount, bigBangInstance, testUser, testUser, testUser);
    }

    function test_revertWhen_amountZero() public {
        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.AmountNotValid.selector);
        tob.lock(testUser, 0, 0, market);
        vm.stopPrank();
    }

    function test_revertWhen_marketNotActive() public {
        address inactiveMarket = makeAddr("inactiveMarket");
        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.MarketNotActive.selector);
        tob.lock(testUser, 0, lockAmount, inactiveMarket);
        vm.stopPrank();
    }

    function test_revertWhen_paused() public {
        vm.startPrank(owner);
        tob.setPause(true);
        vm.stopPrank();

        vm.startPrank(testUser);
        vm.expectRevert("Pausable: paused");
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_revertWhen_emergencySweepActive() public {
        vm.startPrank(owner);
        tob.activateEmergencySweep();
        vm.warp(block.timestamp + 2 days);
        tob.emergencySweep(address(tapToken));
        vm.stopPrank();

        vm.startPrank(testUser);
        vm.expectRevert(ITapiocaOptionBroker.EmergencySweepActivated.selector);
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_lock_validConditions() public {
        _setupValidPosition(3e18, lockAmount);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount);

        Bucket memory bucket = buckets[0];
        uint256 expiry = block.timestamp + (bucket.lockEpochDuration * EPOCH_DURATION);

        uint256 initialTotalUSDO = tob._totalLockedUsdo(testUser);
        int256 initialCurrentEpochDeposits = tob._netDepositsPerEpoch(tob.lastEpoch() + 1);
        int256 initialExpiryEpochDeposits = tob._netDepositsPerEpoch(tob.timestampToEpoch(expiry) + 1);

        tob.lock(testUser, 0, lockAmount, market);

        Participation memory position = tob.getParticipation(testUser, 0);

        uint256 expiryEpoch = tob.timestampToEpoch(position.expiry);
        assertEq(tob._totalLockedUsdo(testUser), initialTotalUSDO + lockAmount, "Total locked USDO should increase");
        assertEq(
            tob._netDepositsPerEpoch(tob.lastEpoch() + 1),
            initialCurrentEpochDeposits + int256(lockAmount),
            "Current epoch deposits should increase"
        );
        assertEq(
            tob._netDepositsPerEpoch(expiryEpoch + 1),
            initialExpiryEpochDeposits - int256(lockAmount),
            "Expiry epoch deposits should decrease"
        );

        vm.stopPrank();
    }

    function test_lock_withExistingPosition_notExpired() public {
        _setupValidPosition(6e18, lockAmount * 3);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        // First lock
        tob.lock(testUser, 0, lockAmount, market);

        // Second lock should also pass
        tob.lock(testUser, 0, lockAmount, market);

        Participation memory position = tob.getParticipation(testUser, 0);
        assertEq(position.totalUsdo, lockAmount * 2, "Total USDO should match the sum of the two locks");

        vm.stopPrank();
    }

    function test_revertWhen_lockToAnotherParticipantWithoutDelegation(address _participant) public {
        vm.assume(_participant != testUser);
        vm.assume(_participant != address(0));

        _setupValidPosition(6e18, lockAmount * 3);

        vm.startPrank(_participant);
        usdo.approve(address(tob), lockAmount * 2);

        // First lock
        vm.expectRevert(ITapiocaOptionBroker.NotAuthorized.selector);
        tob.lock(testUser, 0, lockAmount, market);

        vm.stopPrank();
    }

    function test_lock_withExistingPosition_expired() public {
        _setupValidPosition(6e18, lockAmount * 3);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        // First lock
        tob.lock(testUser, 0, lockAmount, market);

        // Advance time past lock duration
        vm.warp(block.timestamp + (10 * EPOCH_DURATION) + 1);

        // Second lock should succeed
        tob.lock(testUser, 0, lockAmount, market);
        vm.stopPrank();
    }

    function test_expertRevert_when_lockAmountDoesNotMatchExistingBorrowPosition() public {
        _setupValidPosition(3e18, lockAmount);

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        vm.expectRevert(ITapiocaOptionBroker.NotAuthorized.selector);
        tob.lock(testUser, 0, lockAmount * 2, market);

        vm.stopPrank();
    }

    function test_givenAddAssetsReturnsZeroShares_revertWithInvalidShares() public {
        _setupValidPosition(6e18, lockAmount * 3);

        vm.mockCall(
            address(market),
            abi.encodeWithSignature("addAsset(address,address,uint256)"),
            abi.encode(0)
        );

        vm.startPrank(testUser);
        usdo.approve(address(tob), lockAmount * 2);

        vm.expectRevert(ITapiocaOptionBroker.SharesNotValid.selector);
        tob.lock(testUser, 0, lockAmount, market);

        vm.stopPrank();
    }
}
