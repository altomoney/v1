// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersAddContainer is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithoutContainers();
    }

    modifier givenInvalidContainerParameters() {
        _;
    }

    function test_RevertWhen_GrowthRateMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(5, 3, 1, 3, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_GrowthRateMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(0, 3, 1, 3, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_GrowthRateMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 0, 1, 3, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DecayRateMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 5, 3, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DecayRateMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 0, 3, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DecayRateMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 0, 10, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DurationMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 100, 10, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DurationMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 0, 100, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_DurationMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 0, 50);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsGreaterThanDurationMax()
        external
        givenInvalidContainerParameters
    {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 100, 150);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(1, 3, 1, 3, 10, 100, 0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_CurrentDurationEpochsIsNotZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.currentDurationEpochs = 5;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    function test_RevertWhen_IsActiveIsTrue() external givenInvalidContainerParameters {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.isActive = true;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.addContainer(invalidContainer);
    }

    modifier givenValidContainerParameters() {
        _;
    }

    function test_GivenValidContainerParameters() external givenValidContainerParameters {
        uint256 initialCount = containers.totalContainerCount();

        Container memory expectedContainer = defaultContainer;
        expectedContainer.currentDurationEpochs = expectedContainer.duration.min;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(1, expectedContainer);

        // it should return the container ID
        uint256 containerId = containers.addContainer(defaultContainer);

        // it should assign correct container ID starting from 1
        assertEq(containerId, 1);

        // it should increment totalContainerCount
        assertEq(containers.totalContainerCount(), initialCount + 1);

        Container memory storedContainer = containers.getContainer(containerId);

        // it should set currentDurationEpochs to duration min
        assertEq(storedContainer.currentDurationEpochs, defaultContainer.duration.min);

        // it should set isActive to false
        assertFalse(storedContainer.isActive);

        // it should store container with provided parameters
        assertEq(storedContainer.growthRate.min, defaultContainer.growthRate.min);
        assertEq(storedContainer.growthRate.max, defaultContainer.growthRate.max);
        assertEq(storedContainer.decayRate.min, defaultContainer.decayRate.min);
        assertEq(storedContainer.decayRate.max, defaultContainer.decayRate.max);
        assertEq(storedContainer.duration.min, defaultContainer.duration.min);
        assertEq(storedContainer.duration.max, defaultContainer.duration.max);
        assertEq(storedContainer.maxRateDifferenceEpochs, defaultContainer.maxRateDifferenceEpochs);
    }

    function test_AddMultipleContainers() external givenValidContainerParameters {
        Container memory container2 = _createContainerWithCustomParams(2, 4, 1, 2, 5, 50, 25);
        Container memory container3 = _createContainerWithCustomParams(1, 6, 2, 5, 8, 80, 40);

        // Add first container
        uint256 containerId1 = containers.addContainer(defaultContainer);
        assertEq(containerId1, 1);
        assertEq(containers.totalContainerCount(), 1);

        // Add second container
        uint256 containerId2 = containers.addContainer(container2);
        assertEq(containerId2, 2);
        assertEq(containers.totalContainerCount(), 2);

        // Add third container
        uint256 containerId3 = containers.addContainer(container3);
        assertEq(containerId3, 3);
        assertEq(containers.totalContainerCount(), 3);

        // Verify all containers are stored correctly
        Container memory stored1 = containers.getContainer(1);
        Container memory stored2 = containers.getContainer(2);
        Container memory stored3 = containers.getContainer(3);

        assertEq(stored1.growthRate.min, defaultContainer.growthRate.min);
        assertEq(stored2.growthRate.min, container2.growthRate.min);
        assertEq(stored3.growthRate.min, container3.growthRate.min);
    }
}
