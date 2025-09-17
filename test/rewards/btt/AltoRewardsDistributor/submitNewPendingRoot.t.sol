// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {IMerkleRootManagerEvents, IMerkleRootManagerErrors} from "@alto/rewards/interfaces/IMerkleRootManager.sol";

contract AltoRewardsDistributorSubmitNewPendingRoot is RewardsDistributorCommon {
    function setUp() public override {
        super.setUp();
        // Verify no pending root exists after setup
        (bytes32 pendingRoot,,) = distributor.pendingMerkleRoot();
        assert(pendingRoot == bytes32(0));
    }

    function test_RevertWhen_CallerIsNotMerkleRootUpdaterOrOwner() external {
        bytes32 newRoot = bytes32(uint256(123));

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerNotUpdater.selector);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));
    }

    function test_RevertWhen_NewMerkleRootEqualsCurrentPendingRoot() external {
        bytes32 newRoot = bytes32(uint256(123));

        // Submit first time
        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // Try to submit same root again
        vm.prank(UPDATER);
        // it should revert
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerAlreadyPending.selector);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));
    }

    function test_RevertWhen_NewMerkleRootIsZero() external {
        vm.prank(UPDATER);
        // it should revert (since both new and current pending are zero, AlreadyPending is thrown first)
        vm.expectRevert(IMerkleRootManagerErrors.MerkleRootManagerAlreadyPending.selector);
        distributor.submitNewPendingRoot(bytes32(0), bytes32(0));
    }

    modifier whenCallerIsAuthorizedAndInputsAreValid() {
        _;
    }

    function test_WhenCallerIsAuthorizedAndInputsAreValid() external whenCallerIsAuthorizedAndInputsAreValid {
        bytes32 newRoot = bytes32(uint256(123));
        uint256 expectedValidFrom = block.timestamp + INITIAL_TIMELOCK;

        // it should emit SubmitPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.SubmitPendingMerkleRoot(UPDATER, newRoot, bytes32(0));

        vm.prank(UPDATER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // it should set pending merkle root
        (bytes32 pendingRoot, uint256 validFrom, bytes32 ipfsHash) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, newRoot);

        // it should set validFrom timestamp with timelock
        assertEq(validFrom, expectedValidFrom);
    }

    function test_WhenOwnerSubmitsRoot() external whenCallerIsAuthorizedAndInputsAreValid {
        bytes32 newRoot = bytes32(uint256(456));
        uint256 expectedValidFrom = block.timestamp + INITIAL_TIMELOCK;

        // it should emit SubmitPendingMerkleRoot event
        vm.expectEmit(true, true, false, false);
        emit IMerkleRootManagerEvents.SubmitPendingMerkleRoot(OWNER, newRoot, bytes32(0));

        vm.prank(OWNER);
        distributor.submitNewPendingRoot(newRoot, bytes32(0));

        // it should set pending merkle root
        (bytes32 pendingRoot, uint256 validFrom, bytes32 ipfsHash) = distributor.pendingMerkleRoot();
        assertEq(pendingRoot, newRoot);

        // it should set validFrom timestamp with timelock
        assertEq(validFrom, expectedValidFrom);
    }
}
