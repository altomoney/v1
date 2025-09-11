// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoReferralWhitelistAdapterSetReferralWhitelist is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        adapter.setReferralWhitelist(BOB, true);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenSettingAddressToWhitelistedTrue() external whenCallerIsOwner {
        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // it should set referral whitelist mapping to true
        assertTrue(adapter.referralWhitelist(ALICE));
    }

    function test_WhenSettingAddressToWhitelistedFalse() external whenCallerIsOwner {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should set referral whitelist mapping to false
        assertFalse(adapter.referralWhitelist(ALICE));
    }

    function test_WhenUpdatingWhitelistStatusFromFalseToTrue() external whenCallerIsOwner {
        // Verify initial state
        assertFalse(adapter.referralWhitelist(ALICE));

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // it should update referral whitelist mapping
        assertTrue(adapter.referralWhitelist(ALICE));
    }

    function test_WhenUpdatingWhitelistStatusFromTrueToFalse() external whenCallerIsOwner {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);
        assertTrue(adapter.referralWhitelist(ALICE));

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should update referral whitelist mapping
        assertFalse(adapter.referralWhitelist(ALICE));
    }

    function test_WhenSettingWhitelistForMultipleAddresses() external whenCallerIsOwner {
        // Set ALICE to true
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, true);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // Set BOB to true
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(BOB, true);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, true);

        // Set CHARLIE to false
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(CHARLIE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(CHARLIE, false);

        // it should set referral whitelist mapping for each address
        assertTrue(adapter.referralWhitelist(ALICE));
        assertTrue(adapter.referralWhitelist(BOB));
        assertFalse(adapter.referralWhitelist(CHARLIE));
    }
}
