// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {IMerkleRootManagerEvents, IMerkleRootManagerErrors} from "@alto/rewards/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorRevokePendingRoot is RewardsDistributorCommon {
    function test_RevertWhen_CallerIsNotMerkleRootUpdaterOrOwner() external {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root first
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerNotUpdater.selector);
        distributor.revokePendingRoot(newRoot);
    }

    function test_RevertWhen_PendingRootIsNotSet() external {
        // Verify no pending root exists
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));

        vm.prank(UPDATER);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerPendingRootNotSet.selector);
        distributor.revokePendingRoot(bytes32(0));
    }

    function test_RevertWhen_MerkleRootToRevokeIsNonzeroAndDoesNotMatchPendingRoot() external {
        bytes32 newRoot = bytes32(uint256(123));
        bytes32 wrongRoot = bytes32(uint256(456));

        // Submit a pending root first
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        vm.prank(UPDATER);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerInvalidInput.selector);
        distributor.revokePendingRoot(wrongRoot);
    }

    modifier whenCallerIsAuthorizedAndInputsAreValid() {
        _;
    }

    function test_WhenCallerIsAuthorizedAndInputsAreValid() external whenCallerIsAuthorizedAndInputsAreValid {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root first
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // Verify pending root exists
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, newRoot);

        // it should emit RevokePendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.RevokePendingMerkleRoot(UPDATER, newRoot);

        vm.prank(UPDATER);
        distributor.revokePendingRoot(newRoot);

        // it should delete pending root
        (bytes32 pendingRootAfter,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRootAfter, bytes32(0));
    }

    function test_WhenOwnerRevokesRoot() external whenCallerIsAuthorizedAndInputsAreValid {
        bytes32 newRoot = bytes32(uint256(456));

        // Submit a pending root first
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // it should emit RevokePendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.RevokePendingMerkleRoot(OWNER, newRoot);

        vm.prank(OWNER);
        distributor.revokePendingRoot(newRoot);

        // it should delete pending root
        (bytes32 pendingRootAfter,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRootAfter, bytes32(0));
    }

    function test_WhenRevokingWithZeroParameter() external whenCallerIsAuthorizedAndInputsAreValid {
        bytes32 newRoot = bytes32(uint256(789));

        // Submit a pending root first
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // it should emit RevokePendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.RevokePendingMerkleRoot(UPDATER, newRoot);

        // Revoke with zero parameter (means revoke whatever is pending)
        vm.prank(UPDATER);
        distributor.revokePendingRoot(bytes32(0));

        // it should delete pending root
        (bytes32 pendingRootAfter,,) = distributor.pendingMerkleRoot();
        assertEq(pendingRootAfter, bytes32(0));
    }
}
