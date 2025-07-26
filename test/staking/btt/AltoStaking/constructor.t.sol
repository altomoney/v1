// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {AltoStaking} from "@alto/staking/AltoStaking.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {IAltoStakingErrors, IAltoStakingEvents} from "@alto/staking/interfaces/IAltoStaking.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoStakingConstructor is AltoStakingCommon {
    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_LockTokenIsZeroAddress() external givenInvalidInputs {
        Container[] memory containers = new Container[](0);
        uint256[] memory multipliers = new uint256[](0);

        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        new AltoStaking(address(0), OWNER, EPOCH_DURATION, containers, multipliers);
    }

    function test_RevertWhen_OwnerIsZeroAddress() external givenInvalidInputs {
        Container[] memory containers = new Container[](0);
        uint256[] memory multipliers = new uint256[](0);

        // it should revert
        vm.expectRevert();
        new AltoStaking(address(lockToken), address(0), EPOCH_DURATION, containers, multipliers);
    }

    function test_RevertWhen_EpochDurationIsZero() external givenInvalidInputs {
        Container[] memory containers = new Container[](0);
        uint256[] memory multipliers = new uint256[](0);

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new AltoStaking(address(lockToken), OWNER, 0, containers, multipliers);
    }

    function test_RevertWhen_ContainersLengthDoesNotMatchMultipliersLength() external givenInvalidInputs {
        Container[] memory containers = new Container[](1);
        containers[0] = shortContainer;
        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 0.5 ether;
        multipliers[1] = 0.8 ether;

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);
    }

    function test_RevertWhen_ContainerHasInvalidParameters() external givenInvalidInputs {
        Container[] memory containers = new Container[](1);
        containers[0] = _createCustomContainer(0, 1, 1, 2, 1, 5, 3); // growthRate.min = 0 is invalid
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 0.5 ether;

        // it should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);
    }

    function test_RevertWhen_MultiplierIsZero() external givenInvalidInputs {
        Container[] memory containers = new Container[](1);
        containers[0] = shortContainer;
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = 0;

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);
    }

    function test_RevertWhen_MultiplierIsGreaterThanMathPrecision() external givenInvalidInputs {
        Container[] memory containers = new Container[](1);
        containers[0] = shortContainer;
        uint256[] memory multipliers = new uint256[](1);
        multipliers[0] = MATH_PRECISION + 1;

        // it should revert
        vm.expectRevert(IAltoStakingErrors.AltoStakingInvalidInput.selector);
        new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_WhenNoContainersProvided() external givenValidInputs {
        Container[] memory containers = new Container[](0);
        uint256[] memory multipliers = new uint256[](0);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        AltoStaking testStaking = new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);

        // it should set lockToken correctly
        assertEq(testStaking.lockToken(), address(lockToken));

        // it should set owner correctly
        assertEq(testStaking.owner(), OWNER);

        // it should set epoch duration correctly
        assertEq(testStaking.EPOCH_DURATION(), EPOCH_DURATION);

        // it should initialize with zero containers
        assertEq(testStaking.totalContainerCount(), 0);
    }

    function test_WhenValidContainersProvided() external givenValidInputs {
        Container[] memory containers = new Container[](2);
        containers[0] = shortContainer;
        containers[1] = mediumContainer;

        uint256[] memory multipliers = new uint256[](2);
        multipliers[0] = 0.3 ether;
        multipliers[1] = 0.7 ether;

        // Expected containers with currentDurationEpochs set to duration.min
        Container memory expectedContainer1 = shortContainer;
        expectedContainer1.currentDurationEpochs = shortContainer.duration.min;

        Container memory expectedContainer2 = mediumContainer;
        expectedContainer2.currentDurationEpochs = mediumContainer.duration.min;

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.EpochDurationSet(EPOCH_DURATION);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(1, expectedContainer1);

        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerAdded(2, expectedContainer2);

        // The multiplier events are emitted after all containers are added
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerMultiplierUpdated(1, multipliers[0]);

        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerMultiplierUpdated(2, multipliers[1]);

        AltoStaking testStaking = new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);

        // it should set lockToken correctly
        assertEq(testStaking.lockToken(), address(lockToken));

        // it should set owner correctly
        assertEq(testStaking.owner(), OWNER);

        // it should set epoch duration correctly
        assertEq(testStaking.EPOCH_DURATION(), EPOCH_DURATION);

        // it should add all containers with correct IDs
        assertEq(testStaking.totalContainerCount(), 2);

        Container memory storedContainer1 = testStaking.getContainer(1);
        Container memory storedContainer2 = testStaking.getContainer(2);

        assertEq(storedContainer1.currentDurationEpochs, shortContainer.duration.min);
        assertEq(storedContainer2.currentDurationEpochs, mediumContainer.duration.min);

        // it should set container multipliers correctly
        (uint256 multiplier1,) = testStaking.stakingContainerById(1);
        (uint256 multiplier2,) = testStaking.stakingContainerById(2);

        assertEq(multiplier1, multipliers[0]);
        assertEq(multiplier2, multipliers[1]);
    }

    function test_MultiplierValidation() external givenValidInputs {
        Container[] memory containers = new Container[](3);
        containers[0] = shortContainer;
        containers[1] = mediumContainer;
        containers[2] = longContainer;

        uint256[] memory multipliers = new uint256[](3);
        multipliers[0] = 1; // Minimum valid multiplier
        multipliers[1] = MATH_PRECISION / 2; // 50%
        multipliers[2] = MATH_PRECISION; // Maximum valid multiplier

        AltoStaking testStaking = new AltoStaking(address(lockToken), OWNER, EPOCH_DURATION, containers, multipliers);

        (uint256 multiplier1,) = testStaking.stakingContainerById(1);
        (uint256 multiplier2,) = testStaking.stakingContainerById(2);
        (uint256 multiplier3,) = testStaking.stakingContainerById(3);

        assertEq(multiplier1, 1);
        assertEq(multiplier2, MATH_PRECISION / 2);
        assertEq(multiplier3, MATH_PRECISION);
    }
}
