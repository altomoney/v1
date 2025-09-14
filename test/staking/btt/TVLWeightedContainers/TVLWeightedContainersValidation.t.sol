// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {Container, ITVLWeightedContainersErrors} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

/**
 * @title TVLWeightedContainersValidation
 * @notice Shared validation tests for _validateContainer function
 * @dev This contract contains all the validation test cases that are reused across
 *      constructor, addContainer, and updateContainer tests to avoid duplication
 */
abstract contract TVLWeightedContainersValidation is TVLWeightedContainersCommon {
    /**
     * @dev Override this function in child contracts to call the specific function being tested
     * @param container The container to validate
     */
    function _callFunctionUnderTest(Container memory container) internal virtual;

    modifier givenInvalidContainerParameters() {
        _;
    }

    function test_RevertWhen_GrowthRateMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 5,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_GrowthRateMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 0,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_GrowthRateMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 0,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DecayRateMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 5,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DecayRateMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 0,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DecayRateMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 0,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DurationMinIsGreaterThanMax() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 100,
                durationMax: 10,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DurationMinIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 0,
                durationMax: 100,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_DurationMaxIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 0,
                maxRateDifference: 50
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsGreaterThanDurationMax()
        external
        givenInvalidContainerParameters
    {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 150
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_MaxRateDifferenceEpochsIsZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = _createContainerWithCustomParams(
            ContainerParams({
                growthMin: 1,
                growthMax: 3,
                decayMin: 1,
                decayMax: 3,
                durationMin: 10,
                durationMax: 100,
                maxRateDifference: 0
            })
        );

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_CurrentDurationEpochsIsNotZero() external givenInvalidContainerParameters {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.currentDurationEpochs = 5;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }

    function test_RevertWhen_IsActiveIsTrue() external givenInvalidContainerParameters {
        Container memory invalidContainer = defaultContainer;
        invalidContainer.isActive = true;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        _callFunctionUnderTest(invalidContainer);
    }
}

