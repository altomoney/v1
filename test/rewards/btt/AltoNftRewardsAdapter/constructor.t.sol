// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {NftRewardsAdapterCommon} from "./NftRewardsAdapterCommon.t.sol";
import {AltoNftRewardsAdapter} from "@alto/rewards/adapters/AltoNftRewardsAdapter.sol";

contract AltoNftRewardsAdapterConstructor is NftRewardsAdapterCommon {
    function test_RevertWhen_NftAddressIsZeroAddress() external {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidInput.selector);
        new AltoNftRewardsAdapter(address(0), INITIAL_BONUS_DISCOUNT, INITIAL_PAYMENT_TOKEN_SHARE);
    }

    function test_RevertWhen_BonusDiscountIsGreaterThan0_1Ether() external {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidInput.selector);
        new AltoNftRewardsAdapter(address(pearlClubNft), 0.1 ether + 1, INITIAL_PAYMENT_TOKEN_SHARE);
    }

    function test_RevertWhen_PaymentTokenShareIsGreaterThan0_1Ether() external {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoNftRewardsAdapter.AltoNftRewardsInvalidInput.selector);
        new AltoNftRewardsAdapter(address(pearlClubNft), INITIAL_BONUS_DISCOUNT, 0.1 ether + 1);
    }

    function test_WhenAllParametersAreValid() external {
        address nftAddress = address(pearlClubNft);
        uint256 bonusDiscount = 0.08 ether; // 8%
        uint256 paymentTokenShare = 0.06 ether; // 6%

        // it should emit BonusDiscountSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(bonusDiscount);

        // it should emit PaymentTokenShareSet event
        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(paymentTokenShare);

        // it should emit PearlClubNftAddressInitialized event
        vm.expectEmit(true, false, false, false);
        emit AltoNftRewardsAdapter.PearlClubNftAddressInitialized(nftAddress);

        vm.prank(OWNER);
        AltoNftRewardsAdapter newAdapter = new AltoNftRewardsAdapter(nftAddress, bonusDiscount, paymentTokenShare);

        // it should set PEARL_CLUB_NFT_ADDRESS
        assertEq(newAdapter.PEARL_CLUB_NFT_ADDRESS(), nftAddress);

        // it should set bonusDiscount
        assertEq(newAdapter.bonusDiscount(), bonusDiscount);

        // it should set paymentTokenShare
        assertEq(newAdapter.paymentTokenShare(), paymentTokenShare);

        // it should set owner
        assertEq(newAdapter.owner(), OWNER);
    }

    function test_WhenBonusDiscountIsMaximum() external {
        uint256 maxDiscount = 0.1 ether; // 10%

        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(maxDiscount);

        vm.prank(OWNER);
        AltoNftRewardsAdapter newAdapter =
            new AltoNftRewardsAdapter(address(pearlClubNft), maxDiscount, INITIAL_PAYMENT_TOKEN_SHARE);

        assertEq(newAdapter.bonusDiscount(), maxDiscount);
    }

    function test_WhenPaymentTokenShareIsMaximum() external {
        uint256 maxShare = 0.1 ether; // 10%

        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(maxShare);

        vm.prank(OWNER);
        AltoNftRewardsAdapter newAdapter =
            new AltoNftRewardsAdapter(address(pearlClubNft), INITIAL_BONUS_DISCOUNT, maxShare);

        assertEq(newAdapter.paymentTokenShare(), maxShare);
    }

    function test_WhenBonusDiscountIsZero() external {
        uint256 zeroDiscount = 0;

        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.BonusDiscountSet(zeroDiscount);

        vm.prank(OWNER);
        AltoNftRewardsAdapter newAdapter =
            new AltoNftRewardsAdapter(address(pearlClubNft), zeroDiscount, INITIAL_PAYMENT_TOKEN_SHARE);

        assertEq(newAdapter.bonusDiscount(), zeroDiscount);
    }

    function test_WhenPaymentTokenShareIsZero() external {
        uint256 zeroShare = 0;

        vm.expectEmit(false, false, false, true);
        emit AltoNftRewardsAdapter.PaymentTokenShareSet(zeroShare);

        vm.prank(OWNER);
        AltoNftRewardsAdapter newAdapter =
            new AltoNftRewardsAdapter(address(pearlClubNft), INITIAL_BONUS_DISCOUNT, zeroShare);

        assertEq(newAdapter.paymentTokenShare(), zeroShare);
    }
}
