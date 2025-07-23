// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";

contract AltoRewardsDistributorAcceptPendingRoot is RewardsDistributorCommon {
    function test_RevertWhen_PendingRootIsNotSet() external {
        // Verify no pending root exists
        (bytes32 pendingRoot,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorMerkleRootNotSet.selector);
        distributor.acceptPendingRoot(bytes32(0));
    }

    function test_RevertWhen_MerkleRootToAcceptIsNonzeroAndDoesNotMatchPendingRoot() external {
        bytes32 newRoot = bytes32(uint256(123));
        bytes32 wrongRoot = bytes32(uint256(456));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot);

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidInput.selector);
        distributor.acceptPendingRoot(wrongRoot);
    }

    function test_RevertWhen_CallerIsNotOwnerAndTimelockHasNotExpired() external {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot);

        // Try to accept before timelock expires
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorTimelockNotExpired.selector);
        distributor.acceptPendingRoot(newRoot);
    }

    modifier whenConditionsAreMet() {
        _;
    }

    function test_WhenCallerIsOwnerCanBypassTimelock() external whenConditionsAreMet {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot);

        bytes32 oldMerkleRoot = distributor.merkleRoot();

        // it should emit AcceptPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.AcceptPendingMerkleRoot(OWNER, newRoot);

        vm.prank(OWNER);
        distributor.acceptPendingRoot(newRoot);

        // it should set merkle root to pending root
        assertEq(distributor.merkleRoot(), newRoot);
        assertNotEq(distributor.merkleRoot(), oldMerkleRoot); // sanity check

        // it should delete pending root
        (bytes32 pendingRoot,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
    }

    function test_WhenCallerIsNotOwnerButTimelockHasExpired() external whenConditionsAreMet {
        bytes32 newRoot = bytes32(uint256(456));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot);

        // Wait for timelock to expire
        vm.warp(block.timestamp + INITIAL_TIMELOCK + 1);

        bytes32 oldMerkleRoot = distributor.merkleRoot();

        // it should emit AcceptPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.AcceptPendingMerkleRoot(ALICE, newRoot);

        vm.prank(ALICE);
        distributor.acceptPendingRoot(newRoot);

        // it should set merkle root to pending root
        assertEq(distributor.merkleRoot(), newRoot);
        assertNotEq(distributor.merkleRoot(), oldMerkleRoot);

        // it should delete pending root
        (bytes32 pendingRoot,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
    }

    function test_WhenAcceptingWithZeroParameter() external whenConditionsAreMet {
        bytes32 newRoot = bytes32(uint256(789));

        // Submit a pending root
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot);

        // it should emit AcceptPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IRewardsEvents.AcceptPendingMerkleRoot(OWNER, newRoot);

        // Accept with zero parameter (means accept whatever is pending)
        vm.prank(OWNER);
        distributor.acceptPendingRoot(bytes32(0));

        // it should set merkle root to pending root
        assertEq(distributor.merkleRoot(), newRoot);

        // it should delete pending root
        (bytes32 pendingRoot,) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, bytes32(0));
    }
}
