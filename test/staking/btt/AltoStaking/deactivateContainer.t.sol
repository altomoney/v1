// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoStakingCommon.t.sol";

contract AltoStaking_DeactivateContainer_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.deactivateContainer(CONTAINER_ID);
    }

    function test_RevertWhen_ContainerIsNotDeprecated() public {
        // Container should be active but not deprecated
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);
        (, bool isDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isDeprecated, false);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.deactivateContainer(CONTAINER_ID);
    }

    function test_RevertWhen_ContainerDoesNotExist() public {
        uint256 nonExistentId = 999;

        vm.prank(OWNER);
        vm.expectRevert();
        staking.deactivateContainer(nonExistentId);
    }

    function test_DeactivateContainer_WhenActiveAndDeprecated() public {
        // First deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        // Verify container is deprecated but still active
        (, bool isDeprecatedAfter) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isDeprecatedAfter, true);
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerDeactivated(CONTAINER_ID);

        staking.deactivateContainer(CONTAINER_ID);

        // Verify container is now inactive
        Container memory container = staking.getContainer(CONTAINER_ID);
        assertEq(container.isActive, false);
        (, bool stillDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(stillDeprecated, true);
    }

    function test_RevertWhen_ContainerIsAlreadyInactiveAndDeprecated() public {
        // First deprecate and deactivate the container
        vm.startPrank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);
        staking.deactivateContainer(CONTAINER_ID);
        vm.stopPrank();

        // Verify it's inactive and deprecated
        assertEq(staking.getContainer(CONTAINER_ID).isActive, false);
        (, bool isStillDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isStillDeprecated, true);

        // Try to deactivate again - should revert since container is already inactive
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector));
        staking.deactivateContainer(CONTAINER_ID);
    }

    function test_DeactivateContainer_MaxMultiplierContainer() public {
        // Ensure container 3 is the max multiplier container (1.0 ether)
        uint256 maxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(maxContainer, 3); // Should be container 3 with highest multiplier

        // Deprecate and deactivate container 3
        vm.startPrank(OWNER);
        staking.deprecateContainer(3);
        staking.deactivateContainer(3);
        vm.stopPrank();

        // Max multiplier container should have changed
        uint256 newMaxContainer = staking.maxMultiplierStakingContainerId();
        assertNotEq(newMaxContainer, 3);
        assertEq(newMaxContainer, 2); // Should now be container 2 (0.6 ether)
    }

    function test_DeactivateContainer_MultipleContainers() public {
        vm.startPrank(OWNER);

        // Deprecate all containers first
        staking.deprecateContainer(1);
        staking.deprecateContainer(2);
        staking.deprecateContainer(3);

        // Then deactivate them
        staking.deactivateContainer(1);
        staking.deactivateContainer(2);
        staking.deactivateContainer(3);

        vm.stopPrank();

        // All should be inactive and deprecated
        assertEq(staking.getContainer(1).isActive, false);
        assertEq(staking.getContainer(2).isActive, false);
        assertEq(staking.getContainer(3).isActive, false);
        (, bool isDeprecated1) = staking.stakingContainerById(1);
        (, bool isDeprecated2) = staking.stakingContainerById(2);
        (, bool isDeprecated3) = staking.stakingContainerById(3);
        assertEq(isDeprecated1, true);
        assertEq(isDeprecated2, true);
        assertEq(isDeprecated3, true);

        // Max multiplier container should have changed
        uint256 newMaxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(newMaxContainer, 0); // Should be 0 because no containers are active
    }
}
