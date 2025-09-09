// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";

contract AltoReferralWhitelistAdapterActivateReferralWhitelist is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_ProofIsInvalid() external {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid");

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidProof.selector);
        adapter.activateReferralWhitelist(invalidProof);
    }

    function test_RevertGiven_CallerIsAlreadyWhitelisted() external givenUserIsWhitelisted(ALICE) {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterReferralAlreadyActivated.selector);
        adapter.activateReferralWhitelist(aliceProof);
    }

    function test_WhenCallerProvidesValidProofAndIsNotWhitelisted() external {
        // Verify ALICE is not whitelisted initially
        assertFalse(adapter.referralWhitelist(ALICE));

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(ALICE);
        adapter.activateReferralWhitelist(aliceProof);

        // it should set caller as whitelisted
        assertTrue(adapter.referralWhitelist(ALICE));
    }

    function test_WhenMultipleUsersActivateWithValidProofs() external {
        // ALICE activates
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(ALICE);
        adapter.activateReferralWhitelist(aliceProof);

        // BOB activates
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(BOB, true);

        vm.prank(BOB);
        adapter.activateReferralWhitelist(bobProof);

        // CHARLIE activates
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(CHARLIE, true);

        vm.prank(CHARLIE);
        adapter.activateReferralWhitelist(charlieProof);

        // it should set each user as whitelisted
        assertTrue(adapter.referralWhitelist(ALICE));
        assertTrue(adapter.referralWhitelist(BOB));
        assertTrue(adapter.referralWhitelist(CHARLIE));
    }

    function test_WhenUserActivatesAfterBeingRemovedFromWhitelist() external {
        // First activate ALICE
        vm.prank(ALICE);
        adapter.activateReferralWhitelist(aliceProof);
        assertTrue(adapter.referralWhitelist(ALICE));

        // Owner removes ALICE from whitelist
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);
        assertFalse(adapter.referralWhitelist(ALICE));

        // ALICE re-activates
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(ALICE);
        adapter.activateReferralWhitelist(aliceProof);

        // it should re-whitelist the user
        assertTrue(adapter.referralWhitelist(ALICE));
    }
}
