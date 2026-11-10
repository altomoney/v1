// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";

contract AltoReferralWhitelistAdapterActivateReferral is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_ReferralAddressIsNotWhitelisted() external {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAddress.selector);
        adapter.activateReferral(BOB); // BOB is not whitelisted
    }

    function test_RevertWhen_ReferralAddressEqualsCaller() external givenUserIsWhitelisted(ALICE) {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAddress.selector);
        adapter.activateReferral(ALICE); // Self-referral
    }

    function test_RevertGiven_CallerAlreadyHasReferralAddressSetAndCurrentReferralIsWhitelisted()
        external
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // Alice sets BOB as referral
        vm.prank(ALICE);
        adapter.activateReferral(BOB);

        // Alice tries to set CHARLIE as referral (should fail)
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAlreadySet.selector);
        adapter.activateReferral(CHARLIE);
    }

    function test_WhenCallerHasNoPreviousReferral() external givenUserIsWhitelisted(BOB) {
        // it should emit ReferralSet event
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, address(0), BOB);

        vm.prank(ALICE);
        adapter.activateReferral(BOB);

        // it should set referral mapping
        assertEq(adapter.referral(ALICE), BOB);
    }

    function test_WhenCallerHasPreviousReferralButItWasRemovedFromWhitelist()
        external
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // Alice sets BOB as referral
        vm.prank(ALICE);
        adapter.activateReferral(BOB);
        assertEq(adapter.referral(ALICE), BOB);

        // Owner removes BOB from whitelist
        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, false);

        // Now Alice can set CHARLIE as referral
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, BOB, CHARLIE);

        vm.prank(ALICE);
        adapter.activateReferral(CHARLIE);

        // it should set new referral mapping
        assertEq(adapter.referral(ALICE), CHARLIE);
        assertNotEq(adapter.referral(ALICE), BOB); // sanity check
    }

    function test_WhenSettingReferralForDifferentUsers() external givenUserIsWhitelisted(CHARLIE) {
        // Alice sets CHARLIE as referral
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, address(0), CHARLIE);

        vm.prank(ALICE);
        adapter.activateReferral(CHARLIE);

        // BOB sets CHARLIE as referral
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(BOB, address(0), CHARLIE);

        vm.prank(BOB);
        adapter.activateReferral(CHARLIE);

        // it should set referral mapping for each user
        assertEq(adapter.referral(ALICE), CHARLIE);
        assertEq(adapter.referral(BOB), CHARLIE);
    }
}
