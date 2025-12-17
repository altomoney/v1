// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";

contract AltoReferralWhitelistAdapterGetBonusRewardInfo is ReferralWhitelistAdapterCommon {
    function test_WhenUserHasNoReferralAddressSet() external {
        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenUserHasReferralAddressSetToZero() external {
        // Explicitly set referral to zero (though this is the default)
        vm.prank(OWNER);
        adapter.setReferral(ALICE, address(0));

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenReferralAddressIsNotWhitelisted() external givenUserIsWhitelisted(BOB) {
        // Set referral with BOB whitelisted
        vm.prank(OWNER);
        adapter.setReferral(ALICE, BOB);

        // Then remove BOB from whitelist
        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, false);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenUserHasValidReferralSetup_WhenReferralAddressHasNoCustomReceiverSet()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return configured bonus discount
        assertEq(info.bonusDiscount, INITIAL_BONUS_DISCOUNT);

        // it should return configured payment token share
        assertEq(info.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should return referral address as payment token share receiver
        assertEq(info.paymentTokenShareReceiver, BOB);
    }

    function test_WhenUserHasValidReferralSetup_WhenReferralAddressHasCustomReceiverSet()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        // BOB sets a custom receiver
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return configured bonus discount
        assertEq(info.bonusDiscount, INITIAL_BONUS_DISCOUNT);

        // it should return configured payment token share
        assertEq(info.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should return custom receiver address as payment token share receiver
        assertEq(info.paymentTokenShareReceiver, CHARLIE);
    }

    function test_WhenMultipleUsersHaveSameReferralAddress_WhenReferralAddressHasNoCustomReceiverSet()
        external
        givenUserIsWhitelisted(CHARLIE)
        givenUserHasReferral(ALICE, CHARLIE)
        givenUserHasReferral(BOB, CHARLIE)
    {
        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory bobInfo = adapter.getBonusRewardInfo(BOB);

        // it should return same bonus info for all users
        assertEq(aliceInfo.bonusDiscount, bobInfo.bonusDiscount);
        assertEq(aliceInfo.paymentTokenShare, bobInfo.paymentTokenShare);

        // it should return same referral address as receiver
        assertEq(aliceInfo.paymentTokenShareReceiver, CHARLIE);
        assertEq(bobInfo.paymentTokenShareReceiver, CHARLIE);
    }

    function test_WhenMultipleUsersHaveSameReferralAddress_WhenReferralAddressHasCustomReceiverSet()
        external
        givenUserIsWhitelisted(CHARLIE)
        givenUserHasReferral(ALICE, CHARLIE)
        givenUserHasReferral(BOB, CHARLIE)
    {
        // CHARLIE sets a custom receiver
        vm.prank(CHARLIE);
        adapter.setPaymentTokenShareReceiver(DAVE);

        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory bobInfo = adapter.getBonusRewardInfo(BOB);

        // it should return same bonus info for all users
        assertEq(aliceInfo.bonusDiscount, bobInfo.bonusDiscount);
        assertEq(aliceInfo.paymentTokenShare, bobInfo.paymentTokenShare);

        // it should return same custom receiver address for all users
        assertEq(aliceInfo.paymentTokenShareReceiver, DAVE);
        assertEq(bobInfo.paymentTokenShareReceiver, DAVE);
    }

    function test_WhenAdapterConfigurationChangesAfterReferralSet()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        // Get initial receiver address
        BonusRewardInfo memory initialInfo = adapter.getBonusRewardInfo(ALICE);
        address initialReceiver = initialInfo.paymentTokenShareReceiver;

        // Change configuration
        uint256 newDiscount = 0.08 ether; // 8%
        uint256 newShare = 0.06 ether; // 6%

        vm.startPrank(OWNER);
        adapter.setBonusDiscount(newDiscount);
        adapter.setPaymentTokenShare(newShare);
        vm.stopPrank();

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return updated bonus discount
        assertEq(info.bonusDiscount, newDiscount);

        // it should return updated payment token share
        assertEq(info.paymentTokenShare, newShare);

        // it should return same receiver address (referral or custom)
        assertEq(info.paymentTokenShareReceiver, initialReceiver);
    }

    function test_WhenReferralAddressSetsCustomReceiverAfterReferralIsSet()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        // Initially receiver should be BOB (referral address)
        BonusRewardInfo memory initialInfo = adapter.getBonusRewardInfo(ALICE);
        assertEq(initialInfo.paymentTokenShareReceiver, BOB);

        // BOB sets a custom receiver
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return custom receiver address
        assertEq(info.paymentTokenShareReceiver, CHARLIE);
    }

    function test_WhenReferralAddressSetsCustomReceiverAfterReferralIsSet_WhenCustomReceiverIsSetToZeroAddress()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        // BOB sets a custom receiver first
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(CHARLIE);

        // Verify custom receiver is set
        BonusRewardInfo memory infoWithCustom = adapter.getBonusRewardInfo(ALICE);
        assertEq(infoWithCustom.paymentTokenShareReceiver, CHARLIE);

        // BOB resets receiver to zero address
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(address(0));

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return referral address as receiver (default)
        assertEq(info.paymentTokenShareReceiver, BOB);
    }

    function test_WhenReferralAddressIsRemovedFromWhitelistAfterSetting()
        external
        givenUserIsWhitelisted(BOB)
        givenUserHasReferral(ALICE, BOB)
    {
        // Verify initial setup works
        BonusRewardInfo memory initialInfo = adapter.getBonusRewardInfo(ALICE);
        assertEq(initialInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);

        // Remove BOB from whitelist
        vm.prank(OWNER);
        adapter.setReferralWhitelist(BOB, false);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenCallingForDifferentUsersWithDifferentSetups()
        external
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // Set different referrals
        vm.startPrank(OWNER);
        adapter.setReferral(ALICE, BOB);
        adapter.setReferral(DAVE, CHARLIE);
        vm.stopPrank();

        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory daveInfo = adapter.getBonusRewardInfo(DAVE);
        BonusRewardInfo memory eveInfo = adapter.getBonusRewardInfo(EVE); // No referral

        // it should return appropriate bonus info for each user
        // Alice has referral
        assertEq(aliceInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(aliceInfo.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);
        assertEq(aliceInfo.paymentTokenShareReceiver, BOB);

        // Dave has different referral
        assertEq(daveInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(daveInfo.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);
        assertEq(daveInfo.paymentTokenShareReceiver, CHARLIE);

        // Eve has no referral
        assertEq(eveInfo.bonusDiscount, 0);
        assertEq(eveInfo.paymentTokenShare, 0);
        assertEq(eveInfo.paymentTokenShareReceiver, address(0));

        // it should maintain independent states
        assertNotEq(aliceInfo.paymentTokenShareReceiver, daveInfo.paymentTokenShareReceiver);
    }

    function test_WhenCallingForDifferentUsersWithDifferentSetups_WhenDifferentReferralAddressesHaveDifferentCustomReceivers()
        external
        givenUserIsWhitelisted(BOB)
        givenUserIsWhitelisted(CHARLIE)
    {
        // Set different referrals
        vm.startPrank(OWNER);
        adapter.setReferral(ALICE, BOB);
        adapter.setReferral(DAVE, CHARLIE);
        vm.stopPrank();

        // BOB sets custom receiver to EVE
        vm.prank(BOB);
        adapter.setPaymentTokenShareReceiver(EVE);

        // CHARLIE sets custom receiver to DAVE
        vm.prank(CHARLIE);
        adapter.setPaymentTokenShareReceiver(DAVE);

        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory daveInfo = adapter.getBonusRewardInfo(DAVE);

        // it should return respective custom receiver addresses
        assertEq(aliceInfo.paymentTokenShareReceiver, EVE); // BOB's custom receiver
        assertEq(daveInfo.paymentTokenShareReceiver, DAVE); // CHARLIE's custom receiver
    }
}
