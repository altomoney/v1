// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersAdvanceEpoch is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
        containers.activateContainer(1);
        containers.startEpoch();
    }

    function test_RevertGiven_EpochNotStarted() external {
        _deployWithSingleContainer();

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersNotStarted.selector);
        containers.advanceEpoch(1);
    }

    function test_RevertGiven_CurrentEpochNotFinished() external {
        // Current epoch is 0 and hasn't finished yet
        assertEq(containers.currentEpoch(), 0);
        assertEq(containers.nextEpochToProcess(), 0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersCurrentEpochNotFinished.selector);
        containers.advanceEpoch(1);
    }

    modifier givenCurrentEpochFinished() {
        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION + 1);
        _;
    }

    function test_WhenMaxEpochsToProcessIsZero() external givenCurrentEpochFinished {
        // Add some TVL for testing
        vm.warp(block.timestamp - EPOCH_DURATION - 1); // Go back to epoch 0
        containers.updateContainerTVL(1, 1000, 0, 1, true);
        vm.warp(block.timestamp + EPOCH_DURATION + 1); // Return to epoch 1

        uint256 oldNextEpoch = containers.nextEpochToProcess();
        uint256 currentEpoch = containers.currentEpoch();

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.AdvanceEpoch(oldNextEpoch, currentEpoch);

        // it should process all pending epochs
        containers.advanceEpoch(0);

        // it should update nextEpochToProcess to current epoch
        assertEq(containers.nextEpochToProcess(), currentEpoch);
    }

    function test_WhenMaxEpochsToProcessIsLimited() external givenCurrentEpochFinished {
        // Move forward multiple epochs
        vm.warp(block.timestamp + 2 * EPOCH_DURATION);

        uint256 oldNextEpoch = containers.nextEpochToProcess();
        uint256 maxEpochs = 1;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.AdvanceEpoch(oldNextEpoch, oldNextEpoch + maxEpochs);

        // it should process up to maxEpochsToProcess epochs
        containers.advanceEpoch(maxEpochs);

        // it should update nextEpochToProcess accordingly
        assertEq(containers.nextEpochToProcess(), oldNextEpoch + maxEpochs);
    }

    function test_WhenProcessingEpochsWithContainerTVL() external givenCurrentEpochFinished {
        // Go back to add TVL for epoch 0
        vm.warp(block.timestamp - EPOCH_DURATION - 1);
        containers.updateContainerTVL(1, 1000, 0, 1, true);

        // Return to epoch 1 to process
        vm.warp(block.timestamp + EPOCH_DURATION + 1);

        Container memory containerBefore = containers.getContainer(1);

        // it should calculate total TVL for each epoch and update container durations
        containers.advanceEpoch(1);

        Container memory containerAfter = containers.getContainer(1);

        // Verify the container was processed (duration may have changed based on TVL)
        // The duration should be between min and max based on processing logic
        assertTrue(containerAfter.currentDurationEpochs >= containerBefore.duration.min);
        assertTrue(containerAfter.currentDurationEpochs <= containerBefore.duration.max);
    }

    function test_ComplexScenarioWithMultipleContainers() external givenCurrentEpochFinished {
        // Deploy with multiple containers for more complex testing
        Container[] memory multiContainers = new Container[](2);
        multiContainers[0] = defaultContainer;
        multiContainers[1] = _createContainerWithCustomParams(2, 6, 1, 4, 5, 50, 25);

        _deployWithContainers(multiContainers);
        containers.activateContainer(1);
        containers.activateContainer(2);
        containers.startEpoch();

        // Add different TVL amounts to containers
        containers.updateContainerTVL(1, 3000, 0, 1, true);
        containers.updateContainerTVL(2, 1000, 0, 1, true);

        // Move to next epoch
        vm.warp(block.timestamp + EPOCH_DURATION + 1);

        // Process the epoch
        containers.advanceEpoch(1);

        Container memory container1After = containers.getContainer(1);
        Container memory container2After = containers.getContainer(2);

        // Verify containers were processed
        // Container 1 had 75% of TVL (3000/4000), Container 2 had 25% (1000/4000)
        // Both containers should have valid durations within their ranges
        assertTrue(container1After.currentDurationEpochs >= container1After.duration.min);
        assertTrue(container1After.currentDurationEpochs <= container1After.duration.max);
        assertTrue(container2After.currentDurationEpochs >= container2After.duration.min);
        assertTrue(container2After.currentDurationEpochs <= container2After.duration.max);
    }
}
