// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {StakingContainerExtended} from "@alto/staking/interfaces/IAltoStaking.sol";

contract AltoStaking_GetContainerAfterProcessing_Test is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_GivenContainerDoesNotExist_ItShouldReturnEmptyContainerDataWithDefaultValues() public {
        // Container ID 999 doesn't exist
        StakingContainerExtended memory result = staking.getContainerAfterProcessing(999, 0);

        // Should return default/empty values
        assertEq(result.growthRate.min, 0);
        assertEq(result.growthRate.max, 0);
        assertEq(result.decayRate.min, 0);
        assertEq(result.decayRate.max, 0);
        assertEq(result.duration.min, 0);
        assertEq(result.duration.max, 0);
        assertEq(result.maxRateDifferenceEpochs, 0);
        assertEq(result.currentDurationEpochs, 0);
        assertEq(result.multiplier, 0);
        assertFalse(result.isActive);
        assertFalse(result.isDeprecated);
        assertEq(result.currentDurationEpochsNext, 0);
    }

    function test_GivenContainerExistsButIsNotActive_ItShouldReturnContainerDataWithMultiplierAndDeprecatedStatus()
        public
    {
        // Deprecate then deactivate container 1 to test non-active state

        vm.startPrank(OWNER);
        staking.deprecateContainer(1);
        staking.deactivateContainer(1);
        vm.stopPrank();

        StakingContainerExtended memory result = staking.getContainerAfterProcessing(1, 0);

        // Should return actual container data
        assertEq(result.growthRate.min, shortContainer.growthRate.min);
        assertEq(result.growthRate.max, shortContainer.growthRate.max);
        assertEq(result.duration.min, shortContainer.duration.min);
        assertEq(result.duration.max, shortContainer.duration.max);
        assertFalse(result.isActive); // Not activated
        assertTrue(result.isDeprecated); // Deprecated
        assertGt(result.multiplier, 0); // Has multiplier
    }

    function test_GivenContainerExistsAndIsActive_WhenEpochHasNoTVLData_ItShouldReturnContainerWithMinimumDurationAsNextDuration(
    ) public {
        StakingContainerExtended memory result = staking.getContainerAfterProcessing(1, 0);

        // Should return minimum duration as next duration since no TVL
        assertTrue(result.isActive);
        assertEq(result.currentDurationEpochsNext, shortContainer.duration.min);
    }

    function test_GivenContainerExistsAndIsActive_WhenEpochHasTVLData_ItShouldReturnContainerWithCalculatedNextDurationBasedOnTVLShare(
    ) public {
        // Create a position to generate TVL
        deal(address(lockToken), USER, LOCK_AMOUNT);
        vm.startPrank(USER);
        lockToken.approve(address(staking), LOCK_AMOUNT);
        staking.lock(USER, LOCK_AMOUNT, 1, false, 0);
        vm.stopPrank();

        // Advance time to finish the epoch and then advance epoch processing
        StakingContainerExtended memory result = staking.getContainerAfterProcessing(1, 0);

        vm.warp(staking.initializedAtTimestamp() + EPOCH_DURATION + 1);
        staking.advanceEpoch(1);

        StakingContainerExtended memory resultAfter = staking.getContainerAfterProcessing(1, 1);

        // Since this container has 100% TVL share, it should get close to maximum duration
        assertEq(result.currentDurationEpochsNext, resultAfter.currentDurationEpochs);
    }

    function test_GivenContainerExistsAndIsActive_WhenContainerIsDeprecated_ItShouldReturnContainerWithIsDeprecatedSetToTrue(
    ) public {
        // Deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(1);

        StakingContainerExtended memory result = staking.getContainerAfterProcessing(1, 0);

        // Should show as deprecated
        assertTrue(result.isDeprecated);
        assertTrue(result.isActive);
    }

    function test_GivenEpochToProcessIsValid_ItShouldReturnExtendedContainerWithAllFieldsIncludingCurrentDurationEpochsNext(
    ) public {
        StakingContainerExtended memory result = staking.getContainerAfterProcessing(1, 0);

        // Verify all fields are present and properly set
        assertEq(result.growthRate.min, shortContainer.growthRate.min);
        assertEq(result.growthRate.max, shortContainer.growthRate.max);
        assertEq(result.decayRate.min, shortContainer.decayRate.min);
        assertEq(result.decayRate.max, shortContainer.decayRate.max);
        assertEq(result.duration.min, shortContainer.duration.min);
        assertEq(result.duration.max, shortContainer.duration.max);
        assertEq(result.maxRateDifferenceEpochs, shortContainer.maxRateDifferenceEpochs);
        assertEq(result.currentDurationEpochs, shortContainer.duration.min);
        assertGt(result.multiplier, 0);
        assertTrue(result.isActive);
        assertFalse(result.isDeprecated);

        // currentDurationEpochsNext should be calculated (minimum when no TVL)
        assertEq(result.currentDurationEpochsNext, shortContainer.duration.min);
    }
}
