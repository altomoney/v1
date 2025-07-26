// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon, MockTVLWeightedContainers} from "./TVLWeightedContainersCommon.t.sol";
import {
    Container,
    MinMaxEpochs,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersConstructor is TVLWeightedContainersCommon {
    function test_RevertWhen_EpochDurationIsZero() external {
        Container[] memory emptyContainers = new Container[](0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(0, emptyContainers);
    }

    modifier givenInvalidInitialContainers() {
        _;
    }

    function test_RevertWhen_GrowthRateMinIsGreaterThanMax() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(5, 3, 1, 3, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_GrowthRateMinIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(0, 3, 1, 3, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_GrowthRateMaxIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 0, 1, 3, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DecayRateMinIsGreaterThanMax() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 5, 3, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DecayRateMinIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 0, 3, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DecayRateMaxIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 0, 10, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DurationMinIsGreaterThanMax() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 100, 10, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DurationMinIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 0, 100, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_DurationMaxIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 0, 50);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsGreaterThanDurationMax() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 100, 150);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 100, 0);
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_CurrentDurationEpochsIsNotZero() external givenInvalidInitialContainers {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.currentDurationEpochs = 5;
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    function test_RevertWhen_IsActiveIsTrue() external givenInvalidInitialContainers {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.isActive = true;
        Container[] memory containers = new Container[](1);
        containers[0] = invalidContainer;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new MockTVLWeightedContainers(EPOCH_DURATION, containers);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenNoInitialContainersProvided() external givenValidInputs {
        Container[] memory emptyContainers = new Container[](0);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        MockTVLWeightedContainers testContainers = new MockTVLWeightedContainers(EPOCH_DURATION, emptyContainers);

        // it should set EPOCH_DURATION
        assertEq(testContainers.EPOCH_DURATION(), EPOCH_DURATION);

        // it should set initializedAtTimestamp to zero
        assertEq(testContainers.initializedAtTimestamp(), 0);

        // it should set nextEpochToProcess to zero
        assertEq(testContainers.nextEpochToProcess(), 0);

        // it should set totalContainerCount to zero
        assertEq(testContainers.totalContainerCount(), 0);
    }

    function test_WhenValidInitialContainersProvided() external givenValidInputs {
        Container[] memory initialContainers = new Container[](2);
        initialContainers[0] = defaultContainer;
        initialContainers[1] = _createContainerWithCustomParams(2, 4, 1, 2, 5, 50, 25);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        // Create expected containers with currentDurationEpochs set to duration.min
        Container memory expectedContainer1 = defaultContainer;
        expectedContainer1.currentDurationEpochs = defaultContainer.duration.min;

        Container memory expectedContainer2 = _createContainerWithCustomParams(2, 4, 1, 2, 5, 50, 25);
        expectedContainer2.currentDurationEpochs = expectedContainer2.duration.min;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(1, expectedContainer1);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(2, expectedContainer2);

        MockTVLWeightedContainers testContainers = new MockTVLWeightedContainers(EPOCH_DURATION, initialContainers);

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
