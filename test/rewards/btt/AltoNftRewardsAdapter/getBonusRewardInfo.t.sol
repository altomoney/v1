// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {NftRewardsAdapterCommon} from "./NftRewardsAdapterCommon.t.sol";
import {BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";

contract AltoNftRewardsAdapterGetBonusRewardInfo is NftRewardsAdapterCommon {
    function test_WhenUserHasNoReferralNftIdSet() external {
        // ALICE has no referral set by default
        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenUserHasReferralNftIdSetToZero() external {
        // Set referral to zero (cancel)
        vm.prank(ALICE);
        adapter.setNftReferralId(0);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenReferralNftIdIsOwnedByCallerSelfReferral() external {
        // Set ALICE's referral to her own NFT (should be prevented in setter but handle in getter)
        // We'll manipulate storage directly for this test case
        vm.store(
            address(adapter),
            keccak256(abi.encode(ALICE, uint256(2))), // nftReferralId mapping slot
            bytes32(uint256(1)) // ALICE's NFT ID
        );

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return zero bonus info
        assertEq(info.bonusDiscount, 0);
        assertEq(info.paymentTokenShare, 0);
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenNftOwnerIsValidAddress() external {
        // ALICE sets referral to BOB's NFT
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should return configured bonus discount
        assertEq(info.bonusDiscount, INITIAL_BONUS_DISCOUNT);

        // it should return configured payment token share
        assertEq(info.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should return nft owner as payment token share receiver
        assertEq(info.paymentTokenShareReceiver, BOB);
    }

    function test_WhenNftIsBurnedAfterReferralSet() external {
        // ALICE sets referral to BOB's NFT
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        // BOB burns his NFT
        vm.prank(BOB);
        pearlClubNft.burn(2);

        BonusRewardInfo memory info = adapter.getBonusRewardInfo(ALICE);

        // it should still return configured bonus discount
        assertEq(info.bonusDiscount, INITIAL_BONUS_DISCOUNT);

        // it should still return configured payment token share
        assertEq(info.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should return address(0) as payment token share receiver
        // distributor skips the transfer, funds stay in treasury
        assertEq(info.paymentTokenShareReceiver, address(0));
    }

    function test_WhenMultipleUsersHaveSameReferralNft() external {
        // Both ALICE and CHARLIE set referral to BOB's NFT
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        vm.prank(CHARLIE);
        adapter.setNftReferralId(2); // BOB's NFT

        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory charlieInfo = adapter.getBonusRewardInfo(CHARLIE);

        // it should return same bonus info for all users
        assertEq(aliceInfo.bonusDiscount, charlieInfo.bonusDiscount);
        assertEq(aliceInfo.paymentTokenShare, charlieInfo.paymentTokenShare);

        // it should return same nft owner as receiver
        assertEq(aliceInfo.paymentTokenShareReceiver, BOB);
        assertEq(charlieInfo.paymentTokenShareReceiver, BOB);
    }

    function test_WhenAdapterConfigurationChangesAfterReferralSet() external {
        // ALICE sets referral to BOB's NFT
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        // Get initial info
        BonusRewardInfo memory initialInfo = adapter.getBonusRewardInfo(ALICE);
        assertEq(initialInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(initialInfo.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);

        // Owner updates configuration
        uint256 newBonusDiscount = 0.08 ether; // 8%
        uint256 newPaymentTokenShare = 0.06 ether; // 6%

        vm.prank(OWNER);
        adapter.setBonusDiscount(newBonusDiscount);

        vm.prank(OWNER);
        adapter.setPaymentTokenShare(newPaymentTokenShare);

        BonusRewardInfo memory updatedInfo = adapter.getBonusRewardInfo(ALICE);

        // it should return updated bonus discount
        assertEq(updatedInfo.bonusDiscount, newBonusDiscount);

        // it should return updated payment token share
        assertEq(updatedInfo.paymentTokenShare, newPaymentTokenShare);

        // it should return same nft owner as receiver
        assertEq(updatedInfo.paymentTokenShareReceiver, BOB);
    }

    function test_WhenNftIsTransferredAfterReferralSet() external {
        // ALICE sets referral to BOB's NFT
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        // Verify initial state
        BonusRewardInfo memory initialInfo = adapter.getBonusRewardInfo(ALICE);
        assertEq(initialInfo.paymentTokenShareReceiver, BOB);

        // Transfer NFT from BOB to CHARLIE
        vm.prank(BOB);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        pearlClubNft.transferFrom(BOB, CHARLIE, 2);

        // Get info after transfer
        BonusRewardInfo memory afterTransferInfo = adapter.getBonusRewardInfo(ALICE);

        // Should now point to CHARLIE as the new owner
        assertEq(afterTransferInfo.paymentTokenShareReceiver, CHARLIE);
        assertEq(afterTransferInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(afterTransferInfo.paymentTokenShare, INITIAL_PAYMENT_TOKEN_SHARE);
    }

    function test_WhenCallingForDifferentUsers() external {
        // Set up different referrals for different users
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        vm.prank(BOB);
        adapter.setNftReferralId(3); // CHARLIE's NFT

        // CHARLIE has no referral set

        BonusRewardInfo memory aliceInfo = adapter.getBonusRewardInfo(ALICE);
        BonusRewardInfo memory bobInfo = adapter.getBonusRewardInfo(BOB);
        BonusRewardInfo memory charlieInfo = adapter.getBonusRewardInfo(CHARLIE);

        // ALICE should get bonus with BOB as receiver
        assertEq(aliceInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(aliceInfo.paymentTokenShareReceiver, BOB);

        // BOB should get bonus with CHARLIE as receiver
        assertEq(bobInfo.bonusDiscount, INITIAL_BONUS_DISCOUNT);
        assertEq(bobInfo.paymentTokenShareReceiver, CHARLIE);

        // CHARLIE should get no bonus
        assertEq(charlieInfo.bonusDiscount, 0);
        assertEq(charlieInfo.paymentTokenShareReceiver, address(0));
    }
}
