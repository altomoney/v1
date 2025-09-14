// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {TVLWeightedContainersValidation} from "./TVLWeightedContainersValidation.t.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersAddContainer is TVLWeightedContainersValidation {
    function setUp() public override {
        super.setUp();
        _deployWithoutContainers();
    }

    /// @dev Implementation for validation tests - calls addContainer with invalid container
    function _callFunctionUnderTest(Container memory container) internal override {
        containers.addContainer(container);
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
        Container memory container2 = _createContainerWithCustomParams(
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
        Container memory container3 = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 6,
                decayMin: 2,
                decayMax: 5,
                durationMin: 8,
                durationMax: 80,
                maxRateDifference: 40
            })
        );

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
