// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon, PAUSE_TYPE, RESCUE_MODE_PAUSE_TYPE} from "./AltoStakingCommon.t.sol";
import {StakingPosition, IAltoStakingErrors, IAltoStakingEvents} from "@alto/staking/interfaces/IAltoStaking.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract AltoStakingUnlock is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();

        // Create a standard position for testing
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
    }

    function test_RevertGiven_ContractIsPaused() external {
        _pauseContract();

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        _unlockPosition(USER, RECEIVER, 1);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_SenderIsNotAuthorizedForOnBehalf() external givenInvalidInputs {
        // Remove authorization
        vm.prank(USER);
        staking.setAuthorization(address(this), false);

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingUnauthorized.selector);
        _unlockPosition(USER, RECEIVER, 1);
    }

    function test_RevertWhen_ReceiverIsZeroAddress() external givenInvalidInputs {
        // Advance time to make position expired
        _advanceTime(EPOCH_DURATION + 1);

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        _unlockPosition(USER, address(0), 1);
    }

    function test_RevertWhen_PositionDoesNotExist() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingNoPosition.selector);
        _unlockPosition(USER_2, RECEIVER, 1); // USER_2 has no position
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenPositionIsExpiredAndNotInRescueMode() external givenValidInputs {
        // Advance time to make position expired
        _advanceTime(EPOCH_DURATION + 1);

        uint256 receiverBalanceBefore = lockToken.balanceOf(RECEIVER);
        uint256 contractBalanceBefore = lockToken.balanceOf(address(staking));

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.UnlockPosition(address(this), USER, RECEIVER, 1, LOCK_AMOUNT);

        // it should return released amount
        uint256 released = _unlockPosition(USER, RECEIVER, 1);
        assertEq(released, LOCK_AMOUNT);

        // it should transfer tokens to receiver
        assertEq(lockToken.balanceOf(RECEIVER), receiverBalanceBefore + LOCK_AMOUNT);
        assertEq(lockToken.balanceOf(address(staking)), contractBalanceBefore - LOCK_AMOUNT);

        // it should clear position data
        StakingPosition memory position = staking.getPosition(USER, 1);
        _assertPositionEmpty(position);
    }

    function test_RevertWhen_PositionIsNotExpiredAndNotInRescueMode() external givenValidInputs {
        // Position is not expired yet

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingPositionNotExpired.selector);
        _unlockPosition(USER, RECEIVER, 1);
    }

    function test_WhenPositionIsExpiredAndInRescueMode() external givenValidInputs {
        // Advance time to make position expired
        _advanceTime(EPOCH_DURATION + 1);

        // Enable rescue mode
        _enableRescueMode();

        uint256 receiverBalanceBefore = lockToken.balanceOf(RECEIVER);

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.UnlockPosition(address(this), USER, RECEIVER, 1, LOCK_AMOUNT);

        // it should return released amount
        uint256 released = _unlockPosition(USER, RECEIVER, 1);
        assertEq(released, LOCK_AMOUNT);

        // it should transfer tokens to receiver
        assertEq(lockToken.balanceOf(RECEIVER), receiverBalanceBefore + LOCK_AMOUNT);

        // it should clear position data
        StakingPosition memory position = staking.getPosition(USER, 1);
        _assertPositionEmpty(position);
    }

    function test_WhenPositionIsNotExpiredAndInRescueMode() external givenValidInputs {
        // Enable rescue mode
        _enableRescueMode();

        uint256 receiverBalanceBefore = lockToken.balanceOf(RECEIVER);
        uint256 contractBalanceBefore = lockToken.balanceOf(address(staking));

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.UnlockPosition(address(this), USER, RECEIVER, 1, LOCK_AMOUNT);

        // it should return released amount
        uint256 released = _unlockPosition(USER, RECEIVER, 1);
        assertEq(released, LOCK_AMOUNT);

        // it should transfer tokens to receiver
        assertEq(lockToken.balanceOf(RECEIVER), receiverBalanceBefore + LOCK_AMOUNT);
        assertEq(lockToken.balanceOf(address(staking)), contractBalanceBefore - LOCK_AMOUNT);

        // it should clear position data
        StakingPosition memory position = staking.getPosition(USER, 1);
        _assertPositionEmpty(position);

        // it should update container TVL for remaining epochs
        // (TVL should be reduced for future epochs)
        assertEq(staking.epochTVL(0, 1), 0); // Current epoch TVL should be reduced
    }

    function test_UnlockMultiplePositions() external givenValidInputs {
        // Create additional positions
        _lockPosition(USER, LOCK_AMOUNT, 2, false);
        _lockPosition(USER, LOCK_AMOUNT, 3, false);

        // Advance time to make all positions expired
        _advanceTime(EPOCH_DURATION * 3 + 1);

        // Unlock all positions
        uint256 released1 = _unlockPosition(USER, RECEIVER, 1);
        uint256 released2 = _unlockPosition(USER, RECEIVER, 2);
        uint256 released3 = _unlockPosition(USER, RECEIVER, 3);

        assertEq(released1, LOCK_AMOUNT);
        assertEq(released2, LOCK_AMOUNT);
        assertEq(released3, LOCK_AMOUNT);

        // All positions should be empty
        _assertPositionEmpty(staking.getPosition(USER, 1));
        _assertPositionEmpty(staking.getPosition(USER, 2));
        _assertPositionEmpty(staking.getPosition(USER, 3));

        // Receiver should have all tokens
        assertEq(lockToken.balanceOf(RECEIVER), LOCK_AMOUNT * 3);
    }

    function test_UnlockAfterPartialExpiry() external givenValidInputs {
        // Create positions with different durations
        _lockPosition(USER, LOCK_AMOUNT, 2, false); // 2 epoch duration
        _lockPosition(USER, LOCK_AMOUNT, 3, false); // 3 epoch duration

        // Advance time to expire only first position (1 epoch)
        _advanceTime(EPOCH_DURATION + 1);

        // Should be able to unlock first position
        uint256 released1 = _unlockPosition(USER, RECEIVER, 1);
        assertEq(released1, LOCK_AMOUNT);

        // Should not be able to unlock other positions
        vm.expectRevert(IAltoStakingErrors.AltoStakingPositionNotExpired.selector);
        _unlockPosition(USER, RECEIVER, 2);

        vm.expectRevert(IAltoStakingErrors.AltoStakingPositionNotExpired.selector);
        _unlockPosition(USER, RECEIVER, 3);
    }

    function test_RescueModeEarlyUnlock() external givenValidInputs {
        // Create position that won't expire for a while
        _lockPosition(USER_2, LOCK_AMOUNT, 3, false); // 3 epoch duration

        // Enable rescue mode immediately
        _enableRescueMode();

        // Should be able to unlock even though not expired
        uint256 released = _unlockPosition(USER_2, RECEIVER, 3);
        assertEq(released, LOCK_AMOUNT);

        _assertPositionEmpty(staking.getPosition(USER_2, 3));
    }

    function test_UnlockWithDifferentReceivers() external givenValidInputs {
        // Create multiple positions
        _lockPosition(USER, LOCK_AMOUNT, 2, false);
        _lockPosition(USER, LOCK_AMOUNT, 3, false);

        // Advance time to make all positions expired
        _advanceTime(EPOCH_DURATION * 3 + 1);

        address receiver1 = address(0x100);
        address receiver2 = address(0x200);
        address receiver3 = address(0x300);

        // Unlock to different receivers
        _unlockPosition(USER, receiver1, 1);
        _unlockPosition(USER, receiver2, 2);
        _unlockPosition(USER, receiver3, 3);

        // Each receiver should have the correct amount
        assertEq(lockToken.balanceOf(receiver1), LOCK_AMOUNT);
        assertEq(lockToken.balanceOf(receiver2), LOCK_AMOUNT);
        assertEq(lockToken.balanceOf(receiver3), LOCK_AMOUNT);
    }

    function test_PartialTimeAdvancement() external givenValidInputs {
        // Advance time partially
        _advanceTime(EPOCH_DURATION / 2);

        // Should not be able to unlock
        vm.expectRevert(IAltoStakingErrors.AltoStakingPositionNotExpired.selector);
        _unlockPosition(USER, RECEIVER, 1);

        // Advance time to exactly expiry
        _advanceTime(EPOCH_DURATION / 2);

        // Should be able to unlock now
        uint256 released = _unlockPosition(USER, RECEIVER, 1);
        assertEq(released, LOCK_AMOUNT);
    }
}
