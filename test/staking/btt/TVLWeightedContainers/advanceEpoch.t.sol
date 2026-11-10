// SPDX-License-Identifier: GPL-3.0-or-later
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
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        _;
    }

    function test_WhenMaxEpochsToProcessIsZero() external givenCurrentEpochFinished {
        // Add some TVL for testing
        vm.warp(containers.initializedAtTimestamp()); // Go back to epoch 0
        containers.updateContainerTVL(1, 1000, 0, 1, true);
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION * 5 + 1); // Return to epoch 1

        uint256 oldNextEpoch = containers.nextEpochToProcess();
        uint256 currentEpoch = containers.currentEpoch();

        assertNotEq(oldNextEpoch, currentEpoch);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.AdvanceEpoch(oldNextEpoch, currentEpoch);

        // it should process all pending epochs
        containers.advanceEpoch(0);

        // it should update nextEpochToProcess to current epoch
        assertEq(containers.nextEpochToProcess(), currentEpoch);
    }

    function test_WhenMaxEpochsToProcessIsLimited() external givenCurrentEpochFinished {
        // Move forward multiple epochs
        vm.warp(containers.initializedAtTimestamp() + 2 * EPOCH_DURATION);

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
        vm.warp(containers.initializedAtTimestamp());
        containers.updateContainerTVL(1, 1000, 0, 1, true);

        // Return to epoch 1 to process
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);

        Container memory containerBefore = containers.getContainer(1);

        // it should calculate total TVL for each epoch and update container durations
        containers.advanceEpoch(1);

        Container memory containerAfter = containers.getContainer(1);

        // Verify the container was processed
        // The duration should be greater than the previous duration since this is the only container with TVL
        assertGt(containerAfter.currentDurationEpochs, containerBefore.currentDurationEpochs);
    }

    function test_ComplexScenarioWithMultipleContainers() external givenCurrentEpochFinished {
        // Deploy with multiple containers for more complex testing
        Container[] memory multiContainers = new Container[](2);
        multiContainers[0] = defaultContainer;
        multiContainers[1] = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 6,
                decayMin: 1,
                decayMax: 4,
                durationMin: 5,
                durationMax: 50,
                maxRateDifference: 25
            })
        );

        _deployWithContainers(multiContainers);
        containers.activateContainer(1);
        containers.activateContainer(2);
        containers.startEpoch();

        // Add different TVL amounts to containers
        containers.updateContainerTVL(1, 3000, 0, 1, true);
        containers.updateContainerTVL(2, 1000, 0, 1, true);

        // Move to next epoch
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);

        Container memory container1Before = containers.getContainer(1);
        Container memory container2Before = containers.getContainer(2);

        // Process the epoch
        containers.advanceEpoch(1);

        Container memory container1After = containers.getContainer(1);
        Container memory container2After = containers.getContainer(2);

        // Verify containers were processed
        // Both containers should have grown as they had 0 TVL in the previous epoch
        // and had TVL in the current epoch
        assertGt(container1After.currentDurationEpochs, container1Before.currentDurationEpochs);
        assertGt(container2After.currentDurationEpochs, container2Before.currentDurationEpochs);
    }
}
