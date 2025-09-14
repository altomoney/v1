// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {Container, MinMaxEpochs} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersGetContainer is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    function test_ReturnsEmptyContainerWhenContainerIDIsZero() external {
        Container memory container = containers.getContainer(0);

        // it should return empty container
        assertEq(container.growthRate.min, 0);
        assertEq(container.growthRate.max, 0);
        assertEq(container.decayRate.min, 0);
        assertEq(container.decayRate.max, 0);
        assertEq(container.duration.min, 0);
        assertEq(container.duration.max, 0);
        assertFalse(container.isActive);
        assertEq(container.maxRateDifferenceEpochs, 0);
        assertEq(container.currentDurationEpochs, 0);
    }

    function test_ReturnsEmptyContainerWhenContainerIDDoesNotExist() external {
        Container memory container = containers.getContainer(999);

        // it should return empty container
        assertEq(container.growthRate.min, 0);
        assertEq(container.growthRate.max, 0);
        assertEq(container.decayRate.min, 0);
        assertEq(container.decayRate.max, 0);
        assertEq(container.duration.min, 0);
        assertEq(container.duration.max, 0);
        assertFalse(container.isActive);
        assertEq(container.maxRateDifferenceEpochs, 0);
        assertEq(container.currentDurationEpochs, 0);
    }

    function test_ReturnsCorrectContainerDataWhenContainerIDExists() external {
        Container memory container = containers.getContainer(1);

        // it should return correct container data with all fields
        assertEq(container.growthRate.min, defaultContainer.growthRate.min);
        assertEq(container.growthRate.max, defaultContainer.growthRate.max);
        assertEq(container.decayRate.min, defaultContainer.decayRate.min);
        assertEq(container.decayRate.max, defaultContainer.decayRate.max);
        assertEq(container.duration.min, defaultContainer.duration.min);
        assertEq(container.duration.max, defaultContainer.duration.max);
        assertEq(container.isActive, false); // Container starts inactive
        assertEq(container.maxRateDifferenceEpochs, defaultContainer.maxRateDifferenceEpochs);
        assertEq(container.currentDurationEpochs, defaultContainer.duration.min); // Set to duration.min on creation
    }

    function test_ReturnsCorrectDataAfterContainerActivation() external {
        // Activate the container
        containers.activateContainer(1);

        Container memory container = containers.getContainer(1);

        // Should return updated isActive status
        assertTrue(container.isActive);
        // Other fields should remain the same
        assertEq(container.growthRate.min, defaultContainer.growthRate.min);
        assertEq(container.growthRate.max, defaultContainer.growthRate.max);
        assertEq(container.currentDurationEpochs, defaultContainer.duration.min);
    }

    function test_ReturnsCorrectDataForMultipleContainers() external {
        // Add another container with different parameters
        Container memory customContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 6,
                decayMin: 2,
                decayMax: 4,
                durationMin: 5,
                durationMax: 50,
                maxRateDifference: 25
            })
        );
        uint256 containerId2 = containers.addContainer(customContainer);

        // Get both containers
        Container memory container1 = containers.getContainer(1);
        Container memory container2 = containers.getContainer(containerId2);

        // Verify container 1 data
        assertEq(container1.growthRate.min, defaultContainer.growthRate.min);
        assertEq(container1.duration.min, defaultContainer.duration.min);

        // Verify container 2 data
        assertEq(container2.growthRate.min, 2);
        assertEq(container2.growthRate.max, 6);
        assertEq(container2.duration.min, 5);
        assertEq(container2.duration.max, 50);
        assertEq(container2.maxRateDifferenceEpochs, 25);
        assertEq(container2.currentDurationEpochs, 5); // Set to duration.min
    }
}
