// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {TVLWeightedContainersValidation} from "./TVLWeightedContainersValidation.t.sol";
import {
    Container,
    MinMaxEpochs,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MockTVLWeightedContainersMock} from "@alto-test/staking/helpers/MockTVLWeightedContainersMock.sol";

contract TVLWeightedContainersConstructor is TVLWeightedContainersValidation {
    /// @dev Implementation for validation tests - calls constructor with invalid container
    function _callFunctionUnderTest(Container memory container) internal override {
        Container[] memory containers = new Container[](1);
        containers[0] = container;
        new MockTVLWeightedContainersMock(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_EpochDurationIsZero() external {
        Container[] memory emptyContainers = new Container[](0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainersMock(0, emptyContainers);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenNoInitialContainersProvided() external givenValidInputs {
        Container[] memory emptyContainers = new Container[](0);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        MockTVLWeightedContainersMock testContainers =
            new MockTVLWeightedContainersMock(EPOCH_DURATION, emptyContainers);

        // it should set EPOCH_DURATION
        assertEq(testContainers.EPOCH_DURATION(), EPOCH_DURATION);

        // it should set initializedAtTimestamp to zero
        assertEq(testContainers.initializedAtTimestamp(), 0);

        // it should set nextEpochToProcess to zero
        assertEq(testContainers.nextEpochToProcess(), 0);

        // it should set totalContainerCount to zero
        assertEq(testContainers.totalContainerCount(), emptyContainers.length);
    }

    function test_WhenValidInitialContainersProvided() external givenValidInputs {
        Container[] memory initialContainers = new Container[](2);
        initialContainers[0] = defaultContainer;
        initialContainers[1] = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 4,
                decayMin: 1,
                decayMax: 2,
                durationMin: 5,
                durationMax: 50,
                maxRateDifference: 25
            })
        );

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        // Create expected containers with currentDurationEpochs set to duration.min
        Container memory expectedContainer1 = defaultContainer;
        expectedContainer1.currentDurationEpochs = defaultContainer.duration.min;

        Container memory expectedContainer2 = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 4,
                decayMin: 1,
                decayMax: 2,
                durationMin: 5,
                durationMax: 50,
                maxRateDifference: 25
            })
        );
        expectedContainer2.currentDurationEpochs = expectedContainer2.duration.min;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(1, expectedContainer1);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(2, expectedContainer2);

        MockTVLWeightedContainersMock testContainers =
            new MockTVLWeightedContainersMock(EPOCH_DURATION, initialContainers);

        // it should set EPOCH_DURATION
        assertEq(testContainers.EPOCH_DURATION(), EPOCH_DURATION);

        // it should add all containers with correct IDs starting from 1
        // it should increment totalContainerCount for each container
        assertEq(testContainers.totalContainerCount(), 2);

        Container memory container1 = testContainers.getContainer(1);
        Container memory container2 = testContainers.getContainer(2);

        // it should set container currentDurationEpochs to duration min
        assertEq(container1.currentDurationEpochs, defaultContainer.duration.min);
        assertEq(container2.currentDurationEpochs, initialContainers[1].duration.min);

        // it should set container isActive to false
        assertFalse(container1.isActive);
        assertFalse(container2.isActive);

        // Verify container parameters are correctly set
        assertEq(container1.growthRate.min, defaultContainer.growthRate.min);
        assertEq(container1.growthRate.max, defaultContainer.growthRate.max);
        assertEq(container2.growthRate.min, initialContainers[1].growthRate.min);
        assertEq(container2.growthRate.max, initialContainers[1].growthRate.max);
    }
}
