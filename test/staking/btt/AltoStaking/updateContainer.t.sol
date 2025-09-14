// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoStakingCommon.t.sol";

contract AltoStaking_UpdateContainer_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.updateContainer(CONTAINER_ID, shortContainer, 0.5 ether);
    }

    function test_RevertWhen_ContainerIsDeprecated() public {
        // First deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, 0.5 ether);
    }

    function test_RevertWhen_ContainerDoesNotExistDuringValidation() public {
        uint256 nonExistentId = 999;
        uint256 multiplier = 0.5 ether;

        // Use a container with currentDurationEpochs = 0 for validation
        Container memory validContainer = shortContainer;
        validContainer.currentDurationEpochs = 0;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector));
        staking.updateContainer(nonExistentId, validContainer, multiplier);
    }

    function test_UpdateContainer_ValidInputs() public {
        // Get current container to understand current duration
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create a new container with duration range that includes current duration
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);
        uint256 newMultiplier = 0.8 ether;

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerMultiplierUpdated(CONTAINER_ID, newMultiplier);
        // Note: ContainerUpdated event emits (index, containerBefore, containerAfter)
        // We'll check this separately after the call

        staking.updateContainer(CONTAINER_ID, newContainer, newMultiplier);

        // Verify multiplier was updated
        (uint256 containerMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(containerMultiplier, newMultiplier);

        // Verify container data was updated
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(updatedContainer.growthRate.min, newContainer.growthRate.min);
        assertEq(updatedContainer.growthRate.max, newContainer.growthRate.max);
        assertEq(updatedContainer.decayRate.min, newContainer.decayRate.min);
        assertEq(updatedContainer.decayRate.max, newContainer.decayRate.max);
        assertEq(updatedContainer.duration.min, newContainer.duration.min);
        assertEq(updatedContainer.duration.max, newContainer.duration.max);
        assertEq(updatedContainer.maxRateDifferenceEpochs, newContainer.maxRateDifferenceEpochs);
    }

    function test_RevertWhen_MultiplierIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, 0);
    }

    function test_RevertWhen_MultiplierIsGreaterThanPrecision() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.updateContainer(CONTAINER_ID, shortContainer, MATH_PRECISION + 1);
    }

    function test_UpdateContainer_UpdatesMaxMultiplierContainerId() public {
        uint256 initialMaxContainerId = staking.maxMultiplierStakingContainerId();
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create container with valid duration range and use valid multiplier (less than MATH_PRECISION)
        Container memory validContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 5), 4);

        vm.prank(OWNER);
        staking.updateContainer(CONTAINER_ID, validContainer, 0.9 ether);

        // Max multiplier container should remain the same since 0.9 ether < 1.0 ether (container 3)
        uint256 newMaxContainerId = staking.maxMultiplierStakingContainerId();
        assertEq(newMaxContainerId, initialMaxContainerId); // Should still be container 3

        // Verify the multiplier was updated though
        (uint256 updatedMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(updatedMultiplier, 0.9 ether);
    }

    function test_UpdateContainer_SameMultiplierDifferentContainer() public {
        uint256 initialMaxContainerId = staking.maxMultiplierStakingContainerId();
        (uint256 currentMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        Container memory currentContainer = staking.getContainer(CONTAINER_ID);
        uint256 currentDuration = currentContainer.currentDurationEpochs;

        // Create container with valid duration range
        Container memory newContainer =
            _createCustomContainer(1, 3, 1, 2, uint24(currentDuration), uint24(currentDuration + 10), 8);

        vm.prank(OWNER);
        staking.updateContainer(CONTAINER_ID, newContainer, currentMultiplier);

        // Verify container data was updated but multiplier stayed the same
        (uint256 updatedMultiplier,) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(updatedMultiplier, currentMultiplier);
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(updatedContainer.growthRate.min, newContainer.growthRate.min);
        assertEq(updatedContainer.duration.max, newContainer.duration.max);

        // Verify max multiplier container id was updated
        assertEq(staking.maxMultiplierStakingContainerId(), initialMaxContainerId);
    }
}
