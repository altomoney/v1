// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon, PAUSE_TYPE, RESCUE_MODE_PAUSE_TYPE} from "./AltoStakingCommon.t.sol";
import {StakingPosition, IAltoStakingErrors, IAltoStakingEvents} from "@alto/staking/interfaces/IAltoStaking.sol";
import {ITVLWeightedContainersErrors} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

contract AltoStakingLock is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertGiven_ContractIsPaused() external {
        _pauseContract();

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, PAUSE_TYPE));
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
    }

    function test_RevertGiven_ContractIsInRescueMode() external {
        _enableRescueMode();

        // it should revert
        vm.expectRevert(abi.encodeWithSelector(IPausable.IsPaused.selector, RESCUE_MODE_PAUSE_TYPE));
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
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
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
    }

    function test_RevertWhen_OnBehalfIsZeroAddress() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        _lockPosition(address(0), LOCK_AMOUNT, 1, false);
    }

    function test_RevertWhen_AmountIsZero() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        _lockPosition(USER, 0, 1, false);
    }

    function test_RevertWhen_ContainerIsDeprecated() external givenInvalidInputs {
        // Deprecate container
        vm.prank(OWNER);
        staking.deprecateContainer(1);

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingContainerDeprecated.selector);
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
    }

    function test_RevertWhen_ContainerDoesNotExist() external givenInvalidInputs {
        // it should revert (container validation happens in _updateContainerTVL)
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _lockPosition(USER, LOCK_AMOUNT, 999, false);
    }

    function test_RevertWhen_MaxEpochsToLockForIsLessThanContainerDuration() external givenInvalidInputs {
        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingTryingToLockForTooManyEpochs.selector);
        _lockPositionWithMaxEpochs(USER, LOCK_AMOUNT, 3, false, 1); // Container 3 has 3 epochs duration, limiting to 1
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenPositionDoesNotExistAndIsReuseIsFalse() external givenValidInputs {
        uint256 balanceBefore = lockToken.balanceOf(address(this));
        uint256 contractBalanceBefore = lockToken.balanceOf(address(staking));

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.LockPosition(
            address(this), USER, 1, LOCK_AMOUNT, block.timestamp + EPOCH_DURATION, false
        );

        // it should return locked amount
        uint256 returned = _lockPosition(USER, LOCK_AMOUNT, 1, false);
        assertEq(returned, LOCK_AMOUNT);

        StakingPosition memory position = staking.getPosition(USER, 1);

        // it should create new position
        // it should calculate expiry based on current container duration
        _assertPositionEquals(position, LOCK_AMOUNT, block.timestamp + EPOCH_DURATION, block.timestamp);

        // it should transfer tokens from sender
        assertEq(lockToken.balanceOf(address(this)), balanceBefore - LOCK_AMOUNT);
        assertEq(lockToken.balanceOf(address(staking)), contractBalanceBefore + LOCK_AMOUNT);

        // it should update container TVL
        assertEq(staking.epochTVL(0, 1), LOCK_AMOUNT);
    }

    function test_WhenPositionExistsAndIsReuseIsFalse() external givenValidInputs {
        // Create initial position
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        uint256 additionalAmount = 500 ether;
        uint256 totalAmount = LOCK_AMOUNT + additionalAmount;
        uint256 balanceBefore = lockToken.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.LockPosition(
            address(this), USER, 1, totalAmount, block.timestamp + EPOCH_DURATION, false
        );

        // it should return total locked amount
        uint256 returned = _lockPosition(USER, additionalAmount, 1, false);
        assertEq(returned, totalAmount);

        StakingPosition memory position = staking.getPosition(USER, 1);

        // it should update existing position with additional amount
        _assertPositionEquals(position, totalAmount, block.timestamp + EPOCH_DURATION, block.timestamp);

        // it should transfer additional tokens from sender
        assertEq(lockToken.balanceOf(address(this)), balanceBefore - additionalAmount);

        // it should add new TVL with total amount
        assertEq(staking.epochTVL(0, 1), totalAmount);
    }

    function test_WhenPositionExistsAndIsReuseIsTrueWithMatchingAmount() external givenValidInputs {
        // Create initial position
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        uint256 balanceBefore = lockToken.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.LockPosition(
            address(this), USER, 1, LOCK_AMOUNT, block.timestamp + EPOCH_DURATION, true
        );

        // it should return locked amount
        uint256 returned = _lockPosition(USER, LOCK_AMOUNT, 1, true);
        assertEq(returned, LOCK_AMOUNT);

        StakingPosition memory position = staking.getPosition(USER, 1);

        // it should update position expiry without transferring tokens
        _assertPositionEquals(position, LOCK_AMOUNT, block.timestamp + EPOCH_DURATION, block.timestamp);

        // it should not transfer additional tokens
        assertEq(lockToken.balanceOf(address(this)), balanceBefore);

        // it should add new TVL with same amount
        assertEq(staking.epochTVL(0, 1), LOCK_AMOUNT);
    }

    function test_RevertWhen_PositionExistsAndIsReuseIsTrueWithDifferentAmount() external givenValidInputs {
        // Create initial position
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingNoPosition.selector);
        _lockPosition(USER, LOCK_AMOUNT + 100 ether, 1, true);
    }

    function test_WhenEpochNeedsToBeAdvanced() external givenValidInputs {
        // Create initial position
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // Advance time to next epoch
        _advanceEpochs(1);

        // it should advance epoch before processing
        uint256 epochBefore = staking.nextEpochToProcess();

        // it should process position normally
        uint256 returned = _lockPosition(USER_2, LOCK_AMOUNT, 1, false);
        assertEq(returned, LOCK_AMOUNT);

        // it should maintain correct TVL calculations
        uint256 epochAfter = staking.nextEpochToProcess();
        assertTrue(epochAfter > epochBefore, "Epoch should have been advanced");

        StakingPosition memory position = staking.getPosition(USER_2, 1);
        assertTrue(position.amountLocked > 0, "Position should be created");
    }

    function test_MultipleUsersLocking() external givenValidInputs {
        // Lock for first user
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // Lock for second user in same container
        _lockPosition(USER_2, LOCK_AMOUNT * 2, 1, false);

        StakingPosition memory position1 = staking.getPosition(USER, 1);
        StakingPosition memory position2 = staking.getPosition(USER_2, 1);

        assertEq(position1.amountLocked, LOCK_AMOUNT);
        assertEq(position2.amountLocked, LOCK_AMOUNT * 2);

        // TVL should include both positions
        assertEq(staking.epochTVL(0, 1), LOCK_AMOUNT + LOCK_AMOUNT * 2);
    }

    function test_LockingInDifferentContainers() external givenValidInputs {
        // Lock in container 1
        _lockPosition(USER, LOCK_AMOUNT, 1, false);

        // Lock in container 2
        _lockPosition(USER, LOCK_AMOUNT, 2, false);

        StakingPosition memory position1 = staking.getPosition(USER, 1);
        StakingPosition memory position2 = staking.getPosition(USER, 2);

        assertEq(position1.amountLocked, LOCK_AMOUNT);
        assertEq(position2.amountLocked, LOCK_AMOUNT);

        // Each container should have separate TVL
        assertEq(staking.epochTVL(0, 1), LOCK_AMOUNT);
        assertEq(staking.epochTVL(0, 2), LOCK_AMOUNT);
    }

    function test_ExpiryCalculationWithDifferentContainerDurations() external givenValidInputs {
        // Container 1 has duration 1 epoch, container 2 has duration 2 epochs, etc.
        _lockPosition(USER, LOCK_AMOUNT, 1, false);
        _lockPosition(USER, LOCK_AMOUNT, 2, false);
        _lockPosition(USER, LOCK_AMOUNT, 3, false);

        StakingPosition memory position1 = staking.getPosition(USER, 1);
        StakingPosition memory position2 = staking.getPosition(USER, 2);
        StakingPosition memory position3 = staking.getPosition(USER, 3);

        // Different expiry times based on container durations
        assertTrue(position2.expiryTimestamp > position1.expiryTimestamp);
        assertTrue(position3.expiryTimestamp > position2.expiryTimestamp);
    }

    function test_WhenMaxEpochsToLockForIsZero() external givenValidInputs {
        // When maxEpochsToLockFor is 0, there should be no restriction
        uint256 returned = _lockPositionWithMaxEpochs(USER, LOCK_AMOUNT, 3, false, 0);
        assertEq(returned, LOCK_AMOUNT);

        StakingPosition memory position = staking.getPosition(USER, 3);

        // it should create position normally with full container duration
        _assertPositionEquals(position, LOCK_AMOUNT, block.timestamp + 3 * EPOCH_DURATION, block.timestamp);
    }

    function test_WhenMaxEpochsToLockForIsGreaterThanContainerDuration() external givenValidInputs {
        // Container 1 has 1 epoch duration, setting maxEpochsToLockFor to 5 should work fine
        uint256 returned = _lockPositionWithMaxEpochs(USER, LOCK_AMOUNT, 1, false, 5);
        assertEq(returned, LOCK_AMOUNT);

        StakingPosition memory position = staking.getPosition(USER, 1);

        // it should create position normally with container's duration (not the max)
        _assertPositionEquals(position, LOCK_AMOUNT, block.timestamp + EPOCH_DURATION, block.timestamp);
    }

    function test_WhenMaxEpochsToLockForEqualsContainerDuration() external givenValidInputs {
        // Container 2 has 2 epoch duration, setting maxEpochsToLockFor to 2 should work fine
        uint256 returned = _lockPositionWithMaxEpochs(USER, LOCK_AMOUNT, 2, false, 2);
        assertEq(returned, LOCK_AMOUNT);

        StakingPosition memory position = staking.getPosition(USER, 2);

        // it should create position normally
        _assertPositionEquals(position, LOCK_AMOUNT, block.timestamp + 2 * EPOCH_DURATION, block.timestamp);
    }
}
