// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AltoStakingCommon} from "./AltoStakingCommon.t.sol";
import {IAltoStakingErrors, IAltoStakingEvents} from "@alto/staking/interfaces/IAltoStaking.sol";
import {Container} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract AltoStaking_AddContainer_Test is AltoStakingCommon {
    function setUp() public override {
        super.setUp();
        _deployEmpty(); // Start with no containers
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.addContainer(shortContainer, 0.5 ether);
    }

    function test_AddContainer_ValidContainerAndMultiplier() public {
        uint256 multiplier = 0.75 ether;
        uint256 initialCount = staking.totalContainerCount();

        vm.prank(OWNER);
        // Note: The container's currentDurationEpochs will be set to duration.min when added
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerMultiplierUpdated(initialCount + 1, multiplier);

        staking.addContainer(shortContainer, multiplier);

        // Verify container was added
        assertEq(staking.totalContainerCount(), initialCount + 1);

        // Verify multiplier was set
        (uint256 containerMultiplier, bool isDeprecated) = staking.stakingContainerById(initialCount + 1);
        assertEq(containerMultiplier, multiplier);
        assertEq(isDeprecated, false);

        // Verify container is inactive by default
        Container memory container = staking.getContainer(initialCount + 1);
        assertEq(container.isActive, false);

        // Max multiplier container should not be updated (container is inactive)
        assertEq(staking.maxMultiplierStakingContainerId(), 0);
    }

    function test_RevertWhen_MultiplierIsZero() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.addContainer(shortContainer, 0);
    }

    function test_RevertWhen_MultiplierIsGreaterThanPrecision() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.addContainer(shortContainer, MATH_PRECISION + 1);
    }

    function test_AddContainer_MultipleContainers() public {
        vm.startPrank(OWNER);

        staking.addContainer(shortContainer, 0.3 ether);
        staking.addContainer(mediumContainer, 0.6 ether);
        staking.addContainer(longContainer, 1.0 ether);

        vm.stopPrank();

        assertEq(staking.totalContainerCount(), 3);
        (uint256 multiplier1,) = staking.stakingContainerById(1);
        (uint256 multiplier2,) = staking.stakingContainerById(2);
        (uint256 multiplier3,) = staking.stakingContainerById(3);
        assertEq(multiplier1, 0.3 ether);
        assertEq(multiplier2, 0.6 ether);
        assertEq(multiplier3, 1.0 ether);
    }
}
