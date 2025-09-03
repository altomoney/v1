// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AltoStakingCommon.t.sol";

contract AltoStaking_DeprecateContainer_Test is AltoStakingCommon {
    uint256 private constant CONTAINER_ID = 1;

    function setUp() public override {
        super.setUp();
        _setupStandardStaking();
    }

    function test_RevertWhen_CallerIsNotOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        staking.deprecateContainer(CONTAINER_ID);
    }

    function test_RevertWhen_ContainerIsAlreadyDeprecated() public {
        // First deprecate the container
        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        // Verify it's deprecated
        (, bool isDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isDeprecated, true);

        // Try to deprecate again - should revert
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.deprecateContainer(CONTAINER_ID);
    }

    function test_RevertWhen_ContainerDoesNotExist() public {
        uint256 nonExistentId = 999;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IAltoStakingErrors.AltoStakingInvalidInput.selector));
        staking.deprecateContainer(nonExistentId);
    }

    function test_DeprecateContainer_WhenActiveAndNotDeprecated() public {
        // Verify container is active and not deprecated
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);
        (, bool isDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isDeprecated, false);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerDeprecate(CONTAINER_ID);

        staking.deprecateContainer(CONTAINER_ID);

        // Verify container is now deprecated but still active
        (, bool isNowDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isNowDeprecated, true);
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);
    }

    function test_DeprecateContainer_WhenInactiveAndNotDeprecated() public {
        // First deactivate the container (need to set up a fresh container)
        vm.prank(OWNER);
        staking.addContainer(shortContainer, 0.4 ether);

        uint256 newContainerId = staking.totalContainerCount();

        // Container should be inactive by default
        assertEq(staking.getContainer(newContainerId).isActive, false);
        (, bool isNewDeprecated) = staking.stakingContainerById(newContainerId);
        assertEq(isNewDeprecated, false);

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.ContainerDeprecate(newContainerId);

        staking.deprecateContainer(newContainerId);

        // Verify container is now deprecated and still inactive
        (, bool isNewNowDeprecated) = staking.stakingContainerById(newContainerId);
        assertEq(isNewNowDeprecated, true);
        assertEq(staking.getContainer(newContainerId).isActive, false);
    }

    function test_DeprecateContainer_UpdatesMaxMultiplierContainerId() public {
        // Ensure container 3 is the max multiplier container (1.0 ether)
        uint256 maxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(maxContainer, 3); // Should be container 3 with highest multiplier

        // Deprecate container 3
        vm.prank(OWNER);
        vm.expectEmit(true, true, true, true);
        emit IAltoStakingEvents.MaxMultiplierStakingContainerIdUpdated(2, 0.6 ether);

        staking.deprecateContainer(3);

        // Max multiplier container should have changed to container 2
        uint256 newMaxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(newMaxContainer, 2); // Should now be container 2 (0.6 ether)

        // Container 3 should be deprecated but still active
        (, bool isContainer3Deprecated) = staking.stakingContainerById(3);
        assertEq(isContainer3Deprecated, true);
        assertEq(staking.getContainer(3).isActive, true);
    }

    function test_DeprecateContainer_DoesNotChangeMaxMultiplierWhenNotMax() public {
        uint256 initialMaxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(initialMaxContainer, 3); // Should be container 3

        // Deprecate container 1 (not the max multiplier container)
        vm.prank(OWNER);
        staking.deprecateContainer(1);

        // Max multiplier container should remain the same
        uint256 maxContainer = staking.maxMultiplierStakingContainerId();
        assertEq(maxContainer, initialMaxContainer);

        // Container 1 should be deprecated
        (, bool isContainer1Deprecated) = staking.stakingContainerById(1);
        assertEq(isContainer1Deprecated, true);
    }

    function test_DeprecateContainer_AllContainers() public {
        vm.startPrank(OWNER);

        staking.deprecateContainer(1);
        staking.deprecateContainer(2);
        staking.deprecateContainer(3);

        vm.stopPrank();

        // All should be deprecated
        (, bool isDeprecated1) = staking.stakingContainerById(1);
        (, bool isDeprecated2) = staking.stakingContainerById(2);
        (, bool isDeprecated3) = staking.stakingContainerById(3);
        assertEq(isDeprecated1, true);
        assertEq(isDeprecated2, true);
        assertEq(isDeprecated3, true);

        // Because we deprecated all containers, max multiplier container should be 0
        assertEq(staking.maxMultiplierStakingContainerId(), 0);
    }

    function test_DeprecateContainer_PreservesActiveStatus() public {
        // Verify container is initially active
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);

        vm.prank(OWNER);
        staking.deprecateContainer(CONTAINER_ID);

        // Container should still be active but deprecated
        assertEq(staking.getContainer(CONTAINER_ID).isActive, true);
        (, bool isStillDeprecated) = staking.stakingContainerById(CONTAINER_ID);
        assertEq(isStillDeprecated, true);
    }
}
