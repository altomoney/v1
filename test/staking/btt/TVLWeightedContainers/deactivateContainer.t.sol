// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TVLWeightedContainersCommon} from "./TVLWeightedContainersCommon.t.sol";
import {
    Container,
    ITVLWeightedContainersErrors,
    ITVLWeightedContainersEvents
} from "@alto/staking/interfaces/ITVLWeightedContainers.sol";

contract TVLWeightedContainersDeactivateContainer is TVLWeightedContainersCommon {
    function setUp() public override {
        super.setUp();
        _deployWithSingleContainer();
    }

    function test_RevertWhen_ContainerIsNotActive() external {
        // Container 1 exists but is not active by default
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.deactivateContainer(1);
    }

    function test_RevertWhen_ContainerIDDoesNotExistInActiveList() external {
        // Activate container 1
        containers.activateContainer(1);

        // Try to deactivate non-existent container
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.deactivateContainer(999);
    }

    modifier whenContainerIsActive() {
        containers.activateContainer(1);
        _;
    }

    function test_DeactivateContainer() external whenContainerIsActive {
        // Verify container is active before deactivation
        assertTrue(containers.getContainer(1).isActive);
        assertTrue(containers.isContainerActive(1));

        uint256[] memory activeIdsBefore = containers.getActiveContainerIds();
        assertEq(activeIdsBefore.length, 1);
        assertEq(activeIdsBefore[0], 1);

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit ITVLWeightedContainersEvents.ContainerDeactivated(1);

        containers.deactivateContainer(1);

        // it should set container isActive to false
        assertFalse(containers.getContainer(1).isActive);
        assertFalse(containers.isContainerActive(1));

        // it should remove container from activeContainerIds array
        uint256[] memory activeIdsAfter = containers.getActiveContainerIds();
        assertEq(activeIdsAfter.length, 0);
    }

    function test_MaintainArrayIntegrityAfterRemoval() external {
        _deployWithoutContainers();

        // Add and activate multiple containers
        uint256 containerId1 = containers.addContainer(defaultContainer);
        uint256 containerId2 = containers.addContainer(defaultContainer);
        uint256 containerId3 = containers.addContainer(defaultContainer);

        containers.activateContainer(containerId1);
        containers.activateContainer(containerId2);
        containers.activateContainer(containerId3);

        // Verify all are active
        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 3);

        // Deactivate middle container
        containers.deactivateContainer(containerId2);

        // it should maintain array integrity after removal
        uint256[] memory activeIdsAfter = containers.getActiveContainerIds();
        assertEq(activeIdsAfter.length, 2);

        // Verify the remaining containers are still in the array
        bool found1 = false;
        bool found3 = false;

        for (uint256 i = 0; i < activeIdsAfter.length; i++) {
            if (activeIdsAfter[i] == containerId1) found1 = true;
            if (activeIdsAfter[i] == containerId3) found3 = true;
            // Container 2 should not be found
            assertFalse(activeIdsAfter[i] == containerId2);
        }

        assertTrue(found1);
        assertTrue(found3);

        // Verify states
        assertTrue(containers.isContainerActive(containerId1));
        assertFalse(containers.isContainerActive(containerId2));
        assertTrue(containers.isContainerActive(containerId3));
    }

    function test_DeactivateFirstContainerInArray() external {
        _deployWithoutContainers();

        // Add and activate multiple containers
        uint256 containerId1 = containers.addContainer(defaultContainer);
        uint256 containerId2 = containers.addContainer(defaultContainer);
        uint256 containerId3 = containers.addContainer(defaultContainer);

        containers.activateContainer(containerId1);
        containers.activateContainer(containerId2);
        containers.activateContainer(containerId3);

        // Deactivate first container
        containers.deactivateContainer(containerId1);

        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 2);

        // Verify container 1 is not in the array
        for (uint256 i = 0; i < activeIds.length; i++) {
            assertFalse(activeIds[i] == containerId1);
        }

        assertFalse(containers.isContainerActive(containerId1));
        assertTrue(containers.isContainerActive(containerId2));
        assertTrue(containers.isContainerActive(containerId3));
    }

    function test_DeactivateLastContainerInArray() external {
        _deployWithoutContainers();

        // Add and activate multiple containers
        uint256 containerId1 = containers.addContainer(defaultContainer);
        uint256 containerId2 = containers.addContainer(defaultContainer);
        uint256 containerId3 = containers.addContainer(defaultContainer);

        containers.activateContainer(containerId1);
        containers.activateContainer(containerId2);
        containers.activateContainer(containerId3);

        // Deactivate last container
        containers.deactivateContainer(containerId3);

        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 2);

        // Verify container 3 is not in the array
        for (uint256 i = 0; i < activeIds.length; i++) {
            assertFalse(activeIds[i] == containerId3);
        }

        assertTrue(containers.isContainerActive(containerId1));
        assertTrue(containers.isContainerActive(containerId2));
        assertFalse(containers.isContainerActive(containerId3));
    }

    function test_DeactivateAllContainers() external {
        _deployWithoutContainers();

        // Add and activate multiple containers
        uint256 containerId1 = containers.addContainer(defaultContainer);
        uint256 containerId2 = containers.addContainer(defaultContainer);

        containers.activateContainer(containerId1);
        containers.activateContainer(containerId2);

        // Deactivate all containers
        containers.deactivateContainer(containerId1);
        containers.deactivateContainer(containerId2);

        uint256[] memory activeIds = containers.getActiveContainerIds();
        assertEq(activeIds.length, 0);

        assertFalse(containers.isContainerActive(containerId1));
        assertFalse(containers.isContainerActive(containerId2));
    }

    function test_CannotDeactivateAlreadyDeactivatedContainer() external {
        // Activate and then deactivate container
        containers.activateContainer(1);
        containers.deactivateContainer(1);

        // Try to deactivate again
        vm.expectRevert(ITVLWeightedContainersErrors.TVLWeightedContainersInvalidInput.selector);
        containers.deactivateContainer(1);
    }
}
