// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ReferralWhitelistAdapterCommon} from "./ReferralWhitelistAdapterCommon.t.sol";
import {AltoReferralWhitelistAdapter} from "@alto/rewards/adapters/AltoReferralWhitelistAdapter.sol";

contract AltoReferralWhitelistAdapterConstructor is ReferralWhitelistAdapterCommon {
    function test_RevertWhen_BonusDiscountIsGreaterThan0_1Ether() external {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidInput.selector);
        new AltoReferralWhitelistAdapter(0.1 ether + 1, INITIAL_PAYMENT_TOKEN_SHARE);
    }

    function test_RevertWhen_PaymentTokenShareIsGreaterThan0_1Ether() external {
        vm.prank(OWNER);
        // it should revert
        vm.expectRevert(AltoReferralWhitelistAdapter.AltoReferralWhitelistAdapterInvalidInput.selector);
        new AltoReferralWhitelistAdapter(INITIAL_BONUS_DISCOUNT, 0.1 ether + 1);
    }

    function test_WhenAllParametersAreValid() external {
        uint256 bonusDiscount = 0.08 ether; // 8%
        uint256 paymentTokenShare = 0.06 ether; // 6%

        // it should emit BonusDiscountSet event
        vm.expectEmit(false, false, false, true);
        emit AltoReferralWhitelistAdapter.BonusDiscountSet(bonusDiscount);

        // it should emit PaymentTokenShareSet event
        vm.expectEmit(false, false, false, true);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareSet(paymentTokenShare);

        vm.prank(OWNER);
        AltoReferralWhitelistAdapter newAdapter = new AltoReferralWhitelistAdapter(bonusDiscount, paymentTokenShare);

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
        emit AltoReferralWhitelistAdapter.BonusDiscountSet(maxDiscount);

        vm.prank(OWNER);
        AltoReferralWhitelistAdapter newAdapter =
            new AltoReferralWhitelistAdapter(maxDiscount, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should set bonusDiscount
        assertEq(newAdapter.bonusDiscount(), maxDiscount);
    }

    function test_WhenPaymentTokenShareIsMaximum() external {
        uint256 maxShare = 0.1 ether; // 10%

        vm.expectEmit(false, false, false, true);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareSet(maxShare);

        vm.prank(OWNER);
        AltoReferralWhitelistAdapter newAdapter = new AltoReferralWhitelistAdapter(INITIAL_BONUS_DISCOUNT, maxShare);

        // it should set paymentTokenShare
        assertEq(newAdapter.paymentTokenShare(), maxShare);
    }

    function test_WhenBonusDiscountIsZero() external {
        uint256 zeroDiscount = 0;

        vm.expectEmit(false, false, false, true);
        emit AltoReferralWhitelistAdapter.BonusDiscountSet(zeroDiscount);

        vm.prank(OWNER);
        AltoReferralWhitelistAdapter newAdapter =
            new AltoReferralWhitelistAdapter(zeroDiscount, INITIAL_PAYMENT_TOKEN_SHARE);

        // it should set bonusDiscount
        assertEq(newAdapter.bonusDiscount(), zeroDiscount);
    }

    function test_WhenPaymentTokenShareIsZero() external {
        uint256 zeroShare = 0;

        vm.expectEmit(false, false, false, true);
        emit AltoReferralWhitelistAdapter.PaymentTokenShareSet(zeroShare);

        vm.prank(OWNER);
        AltoReferralWhitelistAdapter newAdapter = new AltoReferralWhitelistAdapter(INITIAL_BONUS_DISCOUNT, zeroShare);

        // it should set paymentTokenShare
        assertEq(newAdapter.paymentTokenShare(), zeroShare);
    }
}
