// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {TVLWeightedContainersValidation} from "./TVLWeightedContainersValidation.t.sol";
import {
    Container,
    MinMaxEpochs,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersUpdateContainer is TVLWeightedContainersValidation {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    /// @dev Implementation for validation tests - calls updateContainer with invalid container
    function _callFunctionUnderTest(Container memory container) internal override {
        containers.updateContainer(1, container);
    }

    function test_RevertWhen_NewDurationMinIsGreaterThanCurrentDuration() external {
        // Current duration is set to defaultContainer.duration.min (10) when container is created
        Container memory conflictingContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 5,
                decayMin: 1,
                decayMax: 3,
                durationMin: 15,
                durationMax: 100,
                maxRateDifference: 50 // min=15 > current=10
            })
        );

        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainer(1, conflictingContainer);
    }

    function test_RevertWhen_NewDurationMaxIsLessThanCurrentDuration() external {
        // Current duration is set to defaultContainer.duration.min (10) when container is created
        Container memory conflictingContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 5,
                decayMin: 1,
                decayMax: 3,
                durationMin: 5,
                durationMax: 8,
                maxRateDifference: 5 // max=8 < current=10
            })
        );

        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainer(1, conflictingContainer);
    }

    modifier givenValidParameters() {
        _;
    }

    function test_UpdateContainerWithValidParameters() external givenValidParameters {
        Container memory originalContainer = containers.getContainer(1);

        Container memory newContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 8,
                decayMin: 2,
                decayMax: 5,
                durationMin: 5,
                durationMax: 120,
                maxRateDifference: 60
            })
        );
        // Ensure the input container has correct validation requirements
        assertEq(newContainer.currentDurationEpochs, 0);
        assertEq(newContainer.isActive, false);

        // The event will emit the container with preserved currentDurationEpochs and isActive
        Container memory expectedContainerAfter = Container({
            growthRate: MinMaxEpochs({min: 2, max: 8}),
            decayRate: MinMaxEpochs({min: 2, max: 5}),
            duration: MinMaxEpochs({min: 5, max: 120}),
            isActive: originalContainer.isActive, // Preserved from original
            maxRateDifferenceEpochs: 60,
            currentDurationEpochs: originalContainer.currentDurationEpochs // Preserved from original
        });

        // Expect event emission (the event shows the final container state after preservation)
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerUpdated(1, originalContainer, expectedContainerAfter);

        uint256 returnedId = containers.updateContainer(1, newContainer);

        // it should return the container ID
        assertEq(returnedId, 1);

        Container memory updatedContainer = containers.getContainer(1);

        // it should preserve currentDurationEpochs from original container
        assertEq(updatedContainer.currentDurationEpochs, originalContainer.currentDurationEpochs);

        // it should preserve isActive status from original container
        assertEq(updatedContainer.isActive, originalContainer.isActive);

        // it should update container parameters with new values
        assertEq(updatedContainer.growthRate.min, 2);
        assertEq(updatedContainer.growthRate.max, 8);
        assertEq(updatedContainer.decayRate.min, 2);
        assertEq(updatedContainer.decayRate.max, 5);
        assertEq(updatedContainer.duration.min, 5);
        assertEq(updatedContainer.duration.max, 120);
        assertEq(updatedContainer.maxRateDifferenceEpochs, 60);
    }

    function test_UpdateActiveContainerWithValidDurationRange() external givenValidParameters {
        // Activate container first
        containers.activateContainer(1);

        Container memory originalContainer = containers.getContainer(1);
        assertTrue(originalContainer.isActive);

        // Update with duration range that includes current duration (10)
        Container memory newContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 2,
                growthMax: 8,
                decayMin: 2,
                decayMax: 5,
                durationMin: 8,
                durationMax: 120,
                maxRateDifference: 60 // min=8, max=120 includes current=10
            })
        );

        uint256 returnedId = containers.updateContainer(1, newContainer);
        assertEq(returnedId, 1);

        Container memory updatedContainer = containers.getContainer(1);

        // Should preserve active status and current duration
        assertTrue(updatedContainer.isActive);
        assertEq(updatedContainer.currentDurationEpochs, originalContainer.currentDurationEpochs);

        // Should update other parameters
        assertEq(updatedContainer.growthRate.min, 2);
        assertEq(updatedContainer.duration.min, 8);
        assertEq(updatedContainer.duration.max, 120);
    }

    function test_UpdateInactiveContainerPreservesInactiveStatus() external givenValidParameters {
        // Container starts inactive by default
        Container memory originalContainer = containers.getContainer(1);
        assertFalse(originalContainer.isActive);

        Container memory newContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 3,
                growthMax: 7,
                decayMin: 1,
                decayMax: 4,
                durationMin: 5,
                durationMax: 80,
                maxRateDifference: 40
            })
        );

        containers.updateContainer(1, newContainer);

        Container memory updatedContainer = containers.getContainer(1);

        // Should remain inactive
        assertFalse(updatedContainer.isActive);
        assertEq(updatedContainer.currentDurationEpochs, originalContainer.currentDurationEpochs);
    }

    function test_UpdateContainerWithSameDurationRange() external givenValidParameters {
        // Update with exact same duration range
        Container memory newContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 3,
                growthMax: 7,
                decayMin: 1,
                decayMax: 4,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50 // Same duration range as default
            })
        );

        containers.updateContainer(1, newContainer);

        Container memory updatedContainer = containers.getContainer(1);

        // Duration range should be updated even if same values
        assertEq(updatedContainer.duration.min, 10);
        assertEq(updatedContainer.duration.max, 100);

        // Other parameters should be updated
        assertEq(updatedContainer.growthRate.min, 3);
        assertEq(updatedContainer.growthRate.max, 7);
    }

    function test_RevertWhen_UpdateNonExistentContainer() external {
        Container memory newContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 5,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.updateContainer(999, newContainer);
    }
}
