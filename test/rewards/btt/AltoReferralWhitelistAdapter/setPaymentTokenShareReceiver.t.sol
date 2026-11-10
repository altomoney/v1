// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";

contract AltoReferralWhitelistAdapterSetPaymentTokenShareReceiver is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_CallerIsNotWhitelisted() external {
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidReferralAddress.selector);
        adapter.setPaymentTokenShareReceiver(CHARLIE);
    }

    function test_RevertWhen_SettingReceiverToSameAddressAsCurrentReceiver() external givenUserIsWhitelisted(BOB) {
        // Set initial receiver
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);

        // Try to set to same address
        vm.prank(BOB);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidInput.selector);
        adapter.setPaymentTokenShareReceiver(CHARLIE);
    }

    function test_WhenSettingReceiverToDifferentAddress_WhenCurrentReceiverIsZero()
        external
        givenUserIsWhitelisted(BOB)
    {
        // Verify initial state is zero
        assertEq(adapter.paymentTokenShareReceiver(BOB), address(0));

        // it should emit PaymentTokenShareReceiverSet event
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(BOB, CHARLIE);

        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);

        // it should set payment token share receiver mapping
        assertEq(adapter.paymentTokenShareReceiver(BOB), CHARLIE);
    }

    function test_WhenSettingReceiverToDifferentAddress_WhenCurrentReceiverIsNonZero()
        external
        givenUserIsWhitelisted(BOB)
    {
        // Set initial receiver
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);
        assertEq(adapter.paymentTokenShareReceiver(BOB), CHARLIE);

        // Update to different receiver
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(BOB, DAVE);

        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(DAVE);

        // it should update payment token share receiver mapping
        assertEq(adapter.paymentTokenShareReceiver(BOB), DAVE);
        assertNotEq(adapter.paymentTokenShareReceiver(BOB), CHARLIE);
    }

    function test_WhenSettingReceiverToZeroAddress_WhenCurrentReceiverIsNotZero() external givenUserIsWhitelisted(BOB) {
        // Set initial receiver
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);
        assertEq(adapter.paymentTokenShareReceiver(BOB), CHARLIE);

        // Reset to zero
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(BOB, address(0));

        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(address(0));

        // it should set payment token share receiver mapping to zero
        assertEq(adapter.paymentTokenShareReceiver(BOB), address(0));
    }

    function test_RevertWhen_SettingReceiverToZeroAddress_WhenCurrentReceiverIsAlreadyZero()
        external
        givenUserIsWhitelisted(BOB)
    {
        // Verify initial state is zero
        assertEq(adapter.paymentTokenShareReceiver(BOB), address(0));

        // Try to set to zero again
        vm.prank(BOB);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidInput.selector);
        adapter.setPaymentTokenShareReceiver(address(0));
    }

    function test_WhenMultipleWhitelistedAddressesSetReceivers()
        external
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // BOB sets receiver to DAVE
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(BOB, DAVE);

        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(DAVE);

        // CHARLIE sets receiver to EVE
        vm.expectEmit(true, true, false, false);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareReceiverSet(CHARLIE, EVE);

        vm.prank(CHARLIE);
        adapter.setPaymentTokenShareReceiver(EVE);

        // it should set independent receiver mappings for each address
        assertEq(adapter.paymentTokenShareReceiver(BOB), DAVE);
        assertEq(adapter.paymentTokenShareReceiver(CHARLIE), EVE);
    }
}

