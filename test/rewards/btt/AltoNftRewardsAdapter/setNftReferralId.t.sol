// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {NftRewardsAdapterCommon} from "./NftRewardsAdapterCommon.t.sol";
import {AltoNftRewardsAdapter} from "@alto/rewards/adapters/AltoNftRewardsAdapter.sol";

contract AltoNftRewardsAdapterSetNftReferralId is NftRewardsAdapterCommon {
    function test_RevertWhen_ReferralNftIdIsGreaterThan700() external {
        uint256 invalidId = 701;

        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidReferralNftId.selector);
        adapter.setNftReferralId(invalidId);
    }

    function test_RevertWhen_ReferralNftIdOwnerOfCallReverts() external {
        pearlClubNft.burn(1);

        vm.prank(BOB);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidReferralNftId.selector);
        adapter.setNftReferralId(1);
    }

    function test_RevertWhen_ReferralNftIdIsOwnedByCallerSelfReferral() external {
        // ALICE owns NFT #1, try to set self-referral
        vm.prank(ALICE);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidReferralNftId.selector);
        adapter.setNftReferralId(1);
    }

    function test_WhenSettingReferralIdToZeroCancelingReferral() external {
        // First set a valid referral
        vm.prank(ALICE);
        adapter.setNftReferralId(2); // BOB's NFT

        // Then cancel it
        // it should emit NftReferralIdSet event
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, 0);

        vm.prank(ALICE);
        adapter.setNftReferralId(0);

        // it should update nft referral id
        assertEq(adapter.nftReferralId(ALICE), 0);
    }

    function test_WhenSettingReferralIdToValidOwnedNft() external {
        uint256 referralId = 2; // BOB's NFT

        // it should emit NftReferralIdSet event
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, referralId);

        vm.prank(ALICE);
        adapter.setNftReferralId(referralId);

        // it should update nft referral id
        assertEq(adapter.nftReferralId(ALICE), referralId);
    }

    function test_WhenUpdatingReferralIdMultipleTimes() external {
        uint256 referralId1 = 2; // BOB's NFT
        uint256 referralId2 = 3; // CHARLIE's NFT

        // Set first referral
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, referralId1);

        vm.prank(ALICE);
        adapter.setNftReferralId(referralId1);

        assertEq(adapter.nftReferralId(ALICE), referralId1);

        // Set second referral
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, referralId2);

        vm.prank(ALICE);
        adapter.setNftReferralId(referralId2);

        assertEq(adapter.nftReferralId(ALICE), referralId2);
        assertNotEq(adapter.nftReferralId(ALICE), referralId1);
    }

    function test_WhenDifferentUsersSetReferralIds() external {
        uint256 aliceReferralId = 2; // BOB's NFT
        uint256 bobReferralId = 1; // ALICE's NFT

        // Alice sets referral
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, aliceReferralId);

        vm.prank(ALICE);
        adapter.setNftReferralId(aliceReferralId);

        // Bob sets referral
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(BOB, bobReferralId);

        vm.prank(BOB);
        adapter.setNftReferralId(bobReferralId);

        // it should maintain separate referral ids
        assertEq(adapter.nftReferralId(ALICE), aliceReferralId);
        assertEq(adapter.nftReferralId(BOB), bobReferralId);
    }

    function test_WhenSettingReferralIdAt700() external {
        uint256 maxValidId = 700;

        // it should emit NftReferralIdSet event
        vm.expectEmit(true, true, false, false);
        emit AltoNftRewardsAdapter.NftReferralIdSet(ALICE, maxValidId);

        vm.prank(ALICE);
        adapter.setNftReferralId(maxValidId);

        // it should update nft referral id
        assertEq(adapter.nftReferralId(ALICE), maxValidId);
    }
}
