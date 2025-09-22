// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {IMerkleRootManagerEvents, IMerkleRootManagerErrors} from "@alto/utils/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorAcceptPendingRoot is RewardsDistributorCommon {
    function test_RevertWhen_PendingRootIsNotSet() external {
        // Verify no pending root exists
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerRootNotSet.selector);
        distributor.acceptPendingRoot(bytes32(0));
    }

    function test_RevertWhen_MerkleRootToAcceptIsNonzeroAndDoesNotMatchPendingRoot() external {
        bytes32 newRoot = bytes32(uint256(123));
        bytes32 wrongRoot = bytes32(uint256(456));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerInvalidInput.selector);
        distributor.acceptPendingRoot(wrongRoot);
    }

    function test_RevertWhen_CallerIsNotOwnerAndTimelockHasNotExpired() external {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // Try to accept before timelock expires
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerTimelockNotExpired.selector);
        distributor.acceptPendingRoot(newRoot);
    }

    modifier whenConditionsAreMet() {
        _;
    }

    function test_WhenCallerIsOwnerCanBypassTimelock() external whenConditionsAreMet {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        bytes32 oldMerkleRoot = distributor.merkleRoot();

        // it should emit AcceptPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.AcceptPendingMerkleRoot(OWNER, newRoot, bytes32(0));

        vm.prank(OWNER);
        distributor.acceptPendingRoot(newRoot);

        // it should set merkle root to pending root
        assertEq(distributor.merkleRoot(), newRoot);
        assertNotEq(distributor.merkleRoot(), oldMerkleRoot); // sanity check

        // it should delete pending root
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
    }

    function test_WhenCallerIsNotOwnerButTimelockHasExpired() external whenConditionsAreMet {
        bytes32 newRoot = bytes32(uint256(456));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // Wait for timelock to expire
        vm.warp(block.timestamp + INITIAL_TIMELOCK + 1);

        bytes32 oldMerkleRoot = distributor.merkleRoot();

        // it should emit AcceptPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.AcceptPendingMerkleRoot(ALICE, newRoot, bytes32(0));

        vm.prank(ALICE);
        distributor.acceptPendingRoot(newRoot);

        // it should set merkle root to pending root
        assertEq(distributor.merkleRoot(), newRoot);
        assertNotEq(distributor.merkleRoot(), oldMerkleRoot);

        // it should delete pending root
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
    }
}
