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

    function test_WhenSettingAddressToWhitelistedFalse_WhenPaymentTokenShareReceiverIsNotZero()
        external
        whenCallerIsOwner
    {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // Set payment token share receiver
        vm.prank(ALICE);
        adapter.setPaymentTokenShareReceiver(BOB);
        assertEq(adapter.paymentTokenShareReceiver(ALICE), BOB);

        // it should emit PaymentTokenShareReceiverSet event with zero address
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(ALICE, address(0));

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should set referral whitelist mapping to false
        assertFalse(adapter.referralWhitelist(ALICE));

        // it should reset payment token share receiver to zero
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));
    }

    function test_WhenSettingAddressToWhitelistedFalse_WhenPaymentTokenShareReceiverIsAlreadyZero()
        external
        whenCallerIsOwner
    {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);

        // Verify payment token share receiver is zero
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));

        // it should not emit PaymentTokenShareReceiverSet event
        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should set referral whitelist mapping to false
        assertFalse(adapter.referralWhitelist(ALICE));

        // payment token share receiver should remain zero
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));
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

    function test_WhenUpdatingWhitelistStatusFromTrueToFalse_WhenAddressHasPaymentTokenShareReceiverSet()
        external
        whenCallerIsOwner
    {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);
        assertTrue(adapter.referralWhitelist(ALICE));

        // Set payment token share receiver
        vm.prank(ALICE);
        adapter.setPaymentTokenShareReceiver(BOB);
        assertEq(adapter.paymentTokenShareReceiver(ALICE), BOB);

        // it should emit PaymentTokenShareReceiverSet event with zero address
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(ALICE, address(0));

        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should update referral whitelist mapping
        assertFalse(adapter.referralWhitelist(ALICE));

        // it should reset payment token share receiver to zero
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));
    }

    function test_WhenUpdatingWhitelistStatusFromTrueToFalse_WhenAddressHasNoPaymentTokenShareReceiverSet()
        external
        whenCallerIsOwner
    {
        // First set to true
        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, true);
        assertTrue(adapter.referralWhitelist(ALICE));

        // Verify no payment token share receiver is set
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));

        // it should not emit PaymentTokenShareReceiverSet event (already zero)
        // it should emit ReferralWhitelistSet event
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should update referral whitelist mapping
        assertFalse(adapter.referralWhitelist(ALICE));

        // payment token share receiver should remain zero
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));
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

        // Set payment token share receivers for ALICE and BOB
        vm.prank(ALICE);
        adapter.setPaymentTokenShareReceiver(DAVE);
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(EVE);

        // Remove ALICE and BOB from whitelist
        // it should emit PaymentTokenShareReceiverSet event for ALICE
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(ALICE, address(0));

        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(ALICE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(ALICE, false);

        // it should emit PaymentTokenShareReceiverSet event for BOB
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(BOB, address(0));

        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(BOB, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, false);

        // Set CHARLIE to false (was never whitelisted, so receiver is zero)
        // it should not emit PaymentTokenShareReceiverSet event (receiver is already zero)
        vm.expectEmit(true, false, false, true);
        emit AltoReferralWhitelistAdapter.ReferralWhitelistSet(CHARLIE, false);

        vm.prank(OWNER);
        adapter.setReferralWhitelist(CHARLIE, false);

        // it should set referral whitelist mapping for each address
        assertFalse(adapter.referralWhitelist(ALICE));
        assertFalse(adapter.referralWhitelist(BOB));
        assertFalse(adapter.referralWhitelist(CHARLIE));

        // when removing addresses from whitelist, it should reset payment token share receiver for each removed address
        assertEq(adapter.paymentTokenShareReceiver(ALICE), address(0));
        assertEq(adapter.paymentTokenShareReceiver(BOB), address(0));
        assertEq(adapter.paymentTokenShareReceiver(CHARLIE), address(0));
    }
}
