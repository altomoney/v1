// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersActivateContainer is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    modifier givenInvalidInputs() {
        _;
    }

    function test_RevertWhen_ContainerIsAlreadyActive() external givenInvalidInputs {
        // First activate the container
        containers.activateContainer(1);

        // Try to activate again
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.activateContainer(1);
    }

    function test_RevertWhen_ContainerIDDoesNotExist() external givenInvalidInputs {
        // Try to activate non-existent container
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.activateContainer(999);
    }

    function test_RevertWhen_MaxActiveContainersLimitIsReached() external givenInvalidInputs {
        _deployWithoutContainers();

        // Add and activate containers up to the limit (16)
        for (uint256 i = 0; i < 16; i++) {
            uint256 containerId = containers.addContainer(defaultContainer);
            containers.activateContainer(containerId);
        }

        // Add one more container
        uint256 extraContainerId = containers.addContainer(defaultContainer);

        // Try to activate the 17th container - should revert
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.activateContainer(extraContainerId);
    }

    modifier givenValidInputs() {
        _;
    }

    function test_GivenValidInputs() external givenValidInputs {
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerActivated(1);

        containers.activateContainer(1);

        Container memory container = containers.getContainer(1);

        // it should set container isActive to true
        assertTrue(container.isActive);

        // it should add container to activeContainerIds array
        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 1);
        assertEq(activeIds[0], 1);

        // Verify the container is considered active
        assertTrue(containers.isContainerActive(1));
    }

    function test_ActivateMultipleContainers() external givenValidInputs {
        // Add more containers
        uint256 containerId2 = containers.addContainer(defaultContainer);
        uint256 containerId3 = containers.addContainer(defaultContainer);

        // Activate all containers
        containers.activateContainer(1);
        containers.activateContainer(containerId2);
        containers.activateContainer(containerId3);

        // Verify all are active
        assertTrue(containers.getContainer(1).isActive);
        assertTrue(containers.getContainer(containerId2).isActive);
        assertTrue(containers.getContainer(containerId3).isActive);

        // Verify activeContainerIds array
        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 3);

        // Check that all container IDs are in the active list
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < activeIds.length; i++) {
            if (activeIds[i] == 1) found1 = true;
            if (activeIds[i] == containerId2) found2 = true;
            if (activeIds[i] == containerId3) found3 = true;
        }

        assertTrue(found1);
        assertTrue(found2);
        assertTrue(found3);
    }

    function test_ActivateAfterDeactivate() external givenValidInputs {
        // Activate container
        containers.activateContainer(1);
        assertTrue(containers.getContainer(1).isActive);

        // Deactivate container
        containers.deactivateContainer(1);
        assertFalse(containers.getContainer(1).isActive);

        // Activate again - should work
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerActivated(1);

        containers.activateContainer(1);
        assertTrue(containers.getContainer(1).isActive);

        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 1);
        assertEq(activeIds[0], 1);
    }
}
