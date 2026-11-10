// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "../RewardsDistributorCommon.t.sol";
import {IMerkleRootManagerEvents, IMerkleRootManagerErrors} from "@alto/utils/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorSetMerkleRootUpdater is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        address newUpdater = address(0x999);

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerNotOwner.selector);
        distributor.setMerkleRootUpdater(newUpdater, true);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_UpdaterStatusEqualsCurrentStatus() external whenCallerIsOwner {
        // UPDATER is already set to true in the setup
        bool currentStatus = distributor.isMerkleRootUpdater(UPDATER);
        assertTrue(currentStatus);

        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerInvalidInput.selector);
        distributor.setMerkleRootUpdater(UPDATER, currentStatus);
    }

    function test_WhenUpdaterStatusIsDifferentFromCurrentStatus() external whenCallerIsOwner {
        address newUpdater = address(0x999);

        // Verify newUpdater is not currently an updater
        bool currentStatus = distributor.isMerkleRootUpdater(newUpdater);
        assertFalse(currentStatus);

        // it should emit SetMerkleRootUpdater event
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(newUpdater, true);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(newUpdater, true);

        // it should update merkle root updater status
        assertTrue(distributor.isMerkleRootUpdater(newUpdater));
        assertNotEq(distributor.isMerkleRootUpdater(newUpdater), currentStatus); // sanity check
    }

    function test_WhenRemovingExistingUpdater() external whenCallerIsOwner {
        // UPDATER is already set to true in the setup
        assertTrue(distributor.isMerkleRootUpdater(UPDATER));

        // it should emit SetMerkleRootUpdater event
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(UPDATER, false);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(UPDATER, false);

        // it should update merkle root updater status
        assertFalse(distributor.isMerkleRootUpdater(UPDATER));
    }

    function test_WhenAddingNewUpdater() external whenCallerIsOwner {
        address newUpdater = address(0x888);

        // Verify newUpdater is not currently an updater
        assertFalse(distributor.isMerkleRootUpdater(newUpdater));

        // it should emit SetMerkleRootUpdater event
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(newUpdater, true);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(newUpdater, true);

        // it should update merkle root updater status
        assertTrue(distributor.isMerkleRootUpdater(newUpdater));
    }

    function test_WhenTogglingSameUpdaterMultipleTimes() external whenCallerIsOwner {
        address testUpdater = address(0x777);

        // Start with false
        assertFalse(distributor.isMerkleRootUpdater(testUpdater));

        // Set to true
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(testUpdater, true);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(testUpdater, true);

        assertTrue(distributor.isMerkleRootUpdater(testUpdater));

        // Set back to false
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(testUpdater, false);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(testUpdater, false);

        assertFalse(distributor.isMerkleRootUpdater(testUpdater));

        // Set to true again
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(testUpdater, true);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(testUpdater, true);

        assertTrue(distributor.isMerkleRootUpdater(testUpdater));
    }

    function test_WhenManagingMultipleUpdaters() external whenCallerIsOwner {
        address updater1 = address(0x666);
        address updater2 = address(0x555);
        address updater3 = address(0x444);

        // Add multiple updaters
        vm.startPrank(OWNER);

        distributor.setMerkleRootUpdater(updater1, true);
        distributor.setMerkleRootUpdater(updater2, true);
        distributor.setMerkleRootUpdater(updater3, true);

        vm.stopPrank();

        // Verify all are set
        assertTrue(distributor.isMerkleRootUpdater(updater1));
        assertTrue(distributor.isMerkleRootUpdater(updater2));
        assertTrue(distributor.isMerkleRootUpdater(updater3));

        // Original updater should still be set
        assertTrue(distributor.isMerkleRootUpdater(UPDATER));

        // Remove one
        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(updater2, false);

        // Verify state
        assertTrue(distributor.isMerkleRootUpdater(updater1));
        assertFalse(distributor.isMerkleRootUpdater(updater2));
        assertTrue(distributor.isMerkleRootUpdater(updater3));
        assertTrue(distributor.isMerkleRootUpdater(UPDATER));
    }

    function test_WhenSettingOwnerAsUpdater() external whenCallerIsOwner {
        // Owner should not be an updater by default (owner has special privileges anyway)
        assertFalse(distributor.isMerkleRootUpdater(OWNER));

        // it should emit SetMerkleRootUpdater event
        vm.expectEmit(true, false, false, true);
        emit IMerkleRootManagerEvents.SetMerkleRootUpdater(OWNER, true);

        vm.prank(OWNER);
        distributor.setMerkleRootUpdater(OWNER, true);

        // it should update merkle root updater status
        assertTrue(distributor.isMerkleRootUpdater(OWNER));
    }
}
