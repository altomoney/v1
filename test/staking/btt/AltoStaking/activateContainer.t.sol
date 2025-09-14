// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoStakingCommon.t.sol";

contract AltoStaking_ActivateContainer_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _deployWithThreeContainers();
        // Don't activate containers in setup - we'll do it in tests
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.activateContainer(CONTAINER_ID);
    }

    function test_RevertWhen_ContainerIsDeprecated() public {
        // First deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.activateContainer(CONTAINER_ID);
    }

    function test_ActivateContainer_WhenInactive() public {
        // Verify container is initially inactive
        Container memory container = staking.getContainer(CONTAINER_ID);
        assertEq(container.isActive, false);

        // Verify no max multiplier container set initially
        assertEq(staking.maxMultiplierStakingContainerId(), 0);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerActivated(CONTAINER_ID);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.MaxMultiplierStakingContainerIdUpdated(CONTAINER_ID, 0.3 ether);

        staking.activateContainer(CONTAINER_ID);

        // Verify container is now active
        Container memory updatedContainer = staking.getContainer(CONTAINER_ID);
        assertEq(updatedContainer.isActive, true);

        // Verify max multiplier container was updated
        assertEq(staking.maxMultiplierStakingContainerId(), CONTAINER_ID);
    }

    function test_ActivateContainer_UpdatesMaxMultiplierWithHigherMultiplier() public {
        // Activate container 1 (0.3 ether multiplier) first
        vm.prank(OWNER);
        staking.activateContainer(1);
        assertEq(staking.maxMultiplierStakingContainerId(), 1);

        // Then activate container 3 (1.0 ether multiplier)
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.MaxMultiplierStakingContainerIdUpdated(3, 1.0 ether);

        staking.activateContainer(3);

        // Max multiplier should now be container 3
        assertEq(staking.maxMultiplierStakingContainerId(), 3);
    }

    function test_ActivateContainer_DoesNotChangeMaxMultiplierWithLowerMultiplier() public {
        // Activate container 3 (1.0 ether multiplier) first
        vm.prank(OWNER);
        staking.activateContainer(3);
        assertEq(staking.maxMultiplierStakingContainerId(), 3);

        // Then activate container 1 (0.3 ether multiplier)
        vm.prank(OWNER);
        staking.activateContainer(1);

        // Max multiplier should still be container 3
        assertEq(staking.maxMultiplierStakingContainerId(), 3);
    }

    function test_ActivateContainer_MultipleContainers() public {
        vm.startPrank(OWNER);

        staking.activateContainer(1);
        staking.activateContainer(2);
        staking.activateContainer(3);

        vm.stopPrank();

        // All should be active
        assertEq(staking.getContainer(1).isActive, true);
        assertEq(staking.getContainer(2).isActive, true);
        assertEq(staking.getContainer(3).isActive, true);

        // Max multiplier should be container 3 (highest multiplier: 1.0 ether)
        assertEq(staking.maxMultiplierStakingContainerId(), 3);
    }
}
