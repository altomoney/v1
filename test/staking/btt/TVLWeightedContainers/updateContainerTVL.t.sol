// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersUpdateContainerTVL is TVLWeightedContainersCommon {
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
        containers.updateContainerTVL(1, 1000, 0, 1, true);
    }

    function test_RevertGiven_CurrentEpochAlreadyFinished() external {
        // Advance time to move to epoch 1
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersCurrentEpochAlreadyFinished.selector);
        containers.updateContainerTVL(1, 1000, 0, 1, true);
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_AddingTVLAndFromEpochIsNotCurrentEpoch() external givenInvalidInputs {
        // Advance time to epoch 1
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        containers.advanceEpoch(1);

        // Try to add TVL for epoch 0 when current epoch is 1
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainerTVL(1, 1000, 0, 2, true);
    }

    function test_RevertWhen_FromEpochIsGreaterThanToEpoch() external givenInvalidInputs {
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        containers.advanceEpoch(1);

        uint256 nextEpochToProcess = containers.nextEpochToProcess();
        assertNotEq(nextEpochToProcess, 0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainerTVL(1, 1000, nextEpochToProcess, nextEpochToProcess - 1, true);
    }

    function test_RevertWhen_FromEpochIsLessThanNextEpochToProcess() external givenInvalidInputs {
        // Advance time and process epoch 0
        vm.warp(containers.initializedAtTimestamp() + EPOCH_DURATION + 1);
        containers.advanceEpoch(1);

        uint256 nextEpochToProcess = containers.nextEpochToProcess();

        // Now nextEpochToProcess is 1, trying to update epoch 0 should fail
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainerTVL(1, 1000, nextEpochToProcess - 1, 1, false);
    }

    function test_RevertWhen_ContainerIsNotActive() external givenInvalidInputs {
        // Add and don't activate a second container
        uint256 containerId2 = containers.addContainer(defaultContainer);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainerTVL(containerId2, 1000, 0, 1, true);
    }

    function test_RevertWhen_RemovingMoreTVLThanAvailable() external givenInvalidInputs {
        // First add some TVL
        containers.updateContainerTVL(1, 500, 0, 1, true);

        // Try to remove more than available
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainerTVL(1, 1000, 0, 1, false);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenAddingTVL() external givenValidInputs {
        uint256 amount = 1000;
        uint256 fromEpoch = 0;
        uint256 toEpoch = 2;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerTVLUpdated(fromEpoch, 1, amount, true);

        containers.updateContainerTVL(1, amount, fromEpoch, toEpoch, true);

        // it should update epochTVL for all epochs from fromEpoch to toEpoch
        assertEq(containers.epochTVL(0, 1), amount);
        assertEq(containers.epochTVL(1, 1), amount);
        assertEq(containers.epochTVL(2, 1), 0); // toEpoch is exclusive
    }

    function test_WhenRemovingTVL() external givenValidInputs {
        uint256 amount = 1000;
        uint256 removeAmount = 300;
        uint256 fromEpoch = 0;
        uint256 toEpoch = 2;

        // First add TVL
        containers.updateContainerTVL(1, amount, fromEpoch, toEpoch, true);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerTVLUpdated(fromEpoch, 1, removeAmount, false);

        containers.updateContainerTVL(1, removeAmount, fromEpoch, toEpoch, false);

        // it should update epochTVL for all epochs from fromEpoch to toEpoch
        assertEq(containers.epochTVL(0, 1), amount - removeAmount);
        assertEq(containers.epochTVL(1, 1), amount - removeAmount);
        assertEq(containers.epochTVL(2, 1), 0); // toEpoch is exclusive
    }
}
