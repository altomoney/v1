// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {IAltoStakingErrors, IAltoStakingEvents, Container} from "@alto/staking/interfaces/IAltoStaking.sol";
import {ITVLWeightedContainersErrors} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoStaking_UpdateContainer_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.updateContainer(CONTAINER_ID, shortContainer, 0.5 ether);
    }

    function test_RevertWhen_ContainerIsDeprecated() public {
        // First deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, 0.5 ether);
    }

    function test_RevertWhen_ContainerDoesNotExistDuringValidation() public {
        uint256 nonExistentId = 999;
        uint256 multiplier = 0.5 ether;

        // Use a container with currentDurationEpochs = 0 for validation
        Container memory validContainer = shortContainer;
        validContainer.currentDurationEpochs = 0;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector));
        staking.updateContainer(nonExistentId, validContainer, multiplier);
    }

    function test_GivenEpochsAreNotBehind_GivenValidMultiplier_WhenMultiplierIsNonZero() public {
        // Ensure epochs are caught up before testing
        uint256 currentEpoch = staking.currentEpoch();
        if (staking.nextEpochToProcess() < currentEpoch) {
            staking.advanceEpoch(currentEpoch - staking.nextEpochToProcess());
        }

        uint256 nextEpochToProcessBeforeUpdate = staking.nextEpochToProcess();
        uint256 currentEpochBeforeUpdate = staking.currentEpoch();

        // Verify epochs are not behind
        assertEq(nextEpochToProcessBeforeUpdate, currentEpochBeforeUpdate, "Epochs should be caught up before update");

        // Get current container to understand current duration
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create a new container with duration range that includes current duration
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);
        uint256 newMultiplier = 0.8 ether;

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerMultiplierUpdated(CONTAINER_ID, newMultiplier);
        // Note: ContainerUpdated event emits (index, containerBefore, containerAfter)
        // We'll check this separately after the call

        staking.updateContainer(CONTAINER_ID, newContainer, newMultiplier);

        // Verify epochs were NOT advanced (they were already caught up)
        uint256 nextEpochToProcessAfterUpdate = staking.nextEpochToProcess();
        assertEq(
            nextEpochToProcessAfterUpdate,
            nextEpochToProcessBeforeUpdate,
            "Epochs should not be advanced when already caught up"
        );

        // Verify multiplier was updated
        (uint256 containerMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(containerMultiplier, newMultiplier);

        // Verify container data was updated
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(updatedContainer.growthRate.min, newContainer.growthRate.min);
        assertEq(updatedContainer.growthRate.max, newContainer.growthRate.max);
        assertEq(updatedContainer.decayRate.min, newContainer.decayRate.min);
        assertEq(updatedContainer.decayRate.max, newContainer.decayRate.max);
        assertEq(updatedContainer.duration.min, newContainer.duration.min);
        assertEq(updatedContainer.duration.max, newContainer.duration.max);
        assertEq(updatedContainer.maxRateDifferenceEpochs, newContainer.maxRateDifferenceEpochs);
    }

    function test_GivenEpochsAreNotBehind_GivenValidMultiplier_WhenMultiplierIsZero() public {
        // Ensure epochs are caught up before testing
        uint256 currentEpoch = staking.currentEpoch();
        if (staking.nextEpochToProcess() < currentEpoch) {
            staking.advanceEpoch(currentEpoch - staking.nextEpochToProcess());
        }

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, 0);
    }

    function test_GivenEpochsAreNotBehind_GivenInvalidMultiplierGreaterThanMATH_PRECISION() public {
        // Ensure epochs are caught up before testing
        uint256 currentEpoch = staking.currentEpoch();
        if (staking.nextEpochToProcess() < currentEpoch) {
            staking.advanceEpoch(currentEpoch - staking.nextEpochToProcess());
        }

        uint256 nextEpochToProcessBeforeUpdate = staking.nextEpochToProcess();

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, MATH_PRECISION + 1);

        // Verify epochs were NOT advanced (epoch advancement check happens first but condition is false)
        uint256 nextEpochToProcessAfterRevert = staking.nextEpochToProcess();
        assertEq(
            nextEpochToProcessAfterRevert,
            nextEpochToProcessBeforeUpdate,
            "Epochs should not be advanced when already caught up, even if multiplier validation fails"
        );
    }

    function test_GivenEpochsAreNotBehind_GivenValidMultiplier_WhenCheckingMaxMultiplierContainerUpdates() public {
        // Ensure epochs are caught up before testing
        uint256 currentEpoch = staking.currentEpoch();
        if (staking.nextEpochToProcess() < currentEpoch) {
            staking.advanceEpoch(currentEpoch - staking.nextEpochToProcess());
        }

        uint256 initialMaxContainerId = staking.maxMultiplierStakingContainerId();
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create container with valid duration range and use valid multiplier (less than MATH_PRECISION)
        Container memory validContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);

        vm.prank(OWNER);
        staking.updateContainer(CONTAINER_ID, validContainer, 0.9 ether);

        // Max multiplier container should remain the same since 0.9 ether < 1.0 ether (container 3)
        uint256 newMaxContainerId = staking.maxMultiplierStakingContainerId();
        assertEq(newMaxContainerId, initialMaxContainerId); // Should still be container 3

        // Verify the multiplier was updated though
        (uint256 updatedMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(updatedMultiplier, 0.9 ether);
    }

    function test_GivenEpochsAreNotBehind_WhenUpdatingWithSameMultiplierButDifferentContainerData() public {
        // Ensure epochs are caught up before testing
        uint256 currentEpoch = staking.currentEpoch();
        if (staking.nextEpochToProcess() < currentEpoch) {
            staking.advanceEpoch(currentEpoch - staking.nextEpochToProcess());
        }

        uint256 initialMaxContainerId = staking.maxMultiplierStakingContainerId();
        (uint256 currentMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create container with valid duration range
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 10), 8);

        vm.prank(OWNER);
        staking.updateContainer(CONTAINER_ID, newContainer, currentMultiplier);

        // Verify container data was updated but multiplier stayed the same
        (uint256 updatedMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(updatedMultiplier, currentMultiplier);
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(updatedContainer.growthRate.min, newContainer.growthRate.min);
        assertEq(updatedContainer.duration.max, newContainer.duration.max);

        // Verify max multiplier container id was updated
        assertEq(staking.maxMultiplierStakingContainerId(), initialMaxContainerId);
    }

    function test_GivenEpochsAreBehind_GivenValidMultiplier() public {
        // Advance time by 3 epochs without manually advancing epochs
        // This creates a situation where nextEpochToProcess < currentEpoch()
        _advanceEpochs(3);

        uint256 currentEpochAfterTimeAdvance = staking.currentEpoch();
        uint256 nextEpochToProcessBeforeUpdate = staking.nextEpochToProcess();

        // Verify epochs are behind before updateContainer call
        assertLt(nextEpochToProcessBeforeUpdate, currentEpochAfterTimeAdvance, "Epochs should be behind before update");

        // Get current container to create valid update
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);
        uint256 newMultiplier = 0.5 ether;

        // Call updateContainer - this should advance epochs and update container
        vm.prank(OWNER);
        staking.updateContainer(CONTAINER_ID, newContainer, newMultiplier);

        // Verify epochs were advanced to current epoch
        uint256 nextEpochToProcessAfterUpdate = staking.nextEpochToProcess();
        assertEq(
            nextEpochToProcessAfterUpdate,
            currentEpochAfterTimeAdvance,
            "Epochs should be advanced to current epoch after updateContainer"
        );

        // Verify container multiplier was updated
        (uint256 updatedMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(updatedMultiplier, newMultiplier, "Container multiplier should be updated");

        // Verify container data was updated
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(
            updatedContainer.growthRate.min, newContainer.growthRate.min, "Container growthRate.min should be updated"
        );
        assertEq(
            updatedContainer.growthRate.max, newContainer.growthRate.max, "Container growthRate.max should be updated"
        );
        assertEq(
            updatedContainer.decayRate.min, newContainer.decayRate.min, "Container decayRate.min should be updated"
        );
        assertEq(
            updatedContainer.decayRate.max, newContainer.decayRate.max, "Container decayRate.max should be updated"
        );
        assertEq(updatedContainer.duration.min, newContainer.duration.min, "Container duration.min should be updated");
        assertEq(updatedContainer.duration.max, newContainer.duration.max, "Container duration.max should be updated");
        assertEq(
            updatedContainer.maxRateDifferenceEpochs,
            newContainer.maxRateDifferenceEpochs,
            "Container maxRateDifferenceEpochs should be updated"
        );
    }

    function test_GivenEpochsAreBehind_GivenInvalidMultiplierGreaterThanMATH_PRECISION() public {
        // Advance time by 3 epochs without manually advancing epochs
        // This creates a situation where nextEpochToProcess < currentEpoch()
        _advanceEpochs(3);

        uint256 currentEpochAfterTimeAdvance = staking.currentEpoch();
        uint256 nextEpochToProcessBeforeUpdate = staking.nextEpochToProcess();

        // Verify epochs are behind before updateContainer call
        assertLt(nextEpochToProcessBeforeUpdate, currentEpochAfterTimeAdvance, "Epochs should be behind before update");

        // Get current container to create valid update
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);

        // Call updateContainer with invalid multiplier - should revert
        // Note: Epochs are advanced BEFORE multiplier validation, so epochs will be advanced even if multiplier is invalid
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, newContainer, MATH_PRECISION + 1);
    }
}
