// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AltoReferralWhitelistAdapterSetReferral is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_CallerIsNotOwner() external {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        adapter.setReferral(BOB, CHARLIE);
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_RevertWhen_ReferralAddressIsNotWhitelistedAndNotZeroAddress() external whenCallerIsOwner {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAddress.selector);
        adapter.setReferral(ALICE, BOB); // BOB is not whitelisted
    }

    function test_RevertWhen_ReferredUserEqualsReferralAddress()
        external
        whenCallerIsOwner
        givenUserIsWhitelisted(ALICE)
    {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAddress.selector);
        adapter.setReferral(ALICE, ALICE); // Self-referral
    }

    function test_WhenReferralAddressIsWhitelisted() external whenCallerIsOwner givenUserIsWhitelisted(BOB) {
        // it should emit ReferralSet event
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, address(0), BOB);

        vm.prank(OWNER);
        adapter.setReferral(ALICE, BOB);

        // it should set referral mapping
        assertEq(adapter.referral(ALICE), BOB);
    }

    function test_WhenReferralAddressIsZeroAddress() external whenCallerIsOwner {
        // First set a referral
        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, true);
        vm.prank(OWNER);
        adapter.setReferral(ALICE, BOB);

        // Now reset to zero
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, BOB, address(0));

        vm.prank(OWNER);
        adapter.setReferral(ALICE, address(0));

        // it should set referral mapping to zero
        assertEq(adapter.referral(ALICE), address(0));
    }

    function test_WhenUpdatingExistingReferral()
        external
        whenCallerIsOwner
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // Set initial referral
        vm.prank(OWNER);
        adapter.setReferral(ALICE, BOB);
        assertEq(adapter.referral(ALICE), BOB);

        // Update to new referral
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, BOB, CHARLIE);

        vm.prank(OWNER);
        adapter.setReferral(ALICE, CHARLIE);

        // it should update referral mapping
        assertEq(adapter.referral(ALICE), CHARLIE);
        assertNotEq(adapter.referral(ALICE), BOB);
    }

    function test_WhenSettingReferralForMultipleUsers() external whenCallerIsOwner givenUserIsWhitelisted(CHARLIE) {
        // Set referral for ALICE
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(ALICE, address(0), CHARLIE);

        vm.prank(OWNER);
        adapter.setReferral(ALICE, CHARLIE);

        // Set referral for BOB
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.ReferralSet(BOB, address(0), CHARLIE);

        vm.prank(OWNER);
        adapter.setReferral(BOB, CHARLIE);

        // it should set referral mapping for each user
        assertEq(adapter.referral(ALICE), CHARLIE);
        assertEq(adapter.referral(BOB), CHARLIE);
    }
}
