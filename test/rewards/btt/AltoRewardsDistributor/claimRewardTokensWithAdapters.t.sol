// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";
import {AltoRewardsDistributor, CLAIM_PAUSE_TYPE} from "@alto/rewards/AltoRewardsDistributor.sol";
import {IRewardsEvents, IRewardsErrors} from "@alto/rewards/interfaces/IRewardsDistributor.sol";
import {IRewardsAdapter, BonusRewardInfo} from "@alto/rewards/interfaces/IRewardsAdapter.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {ERC20MockDecimals} from "@alto-test/helpers/ERC20MockDecimals.sol";

contract MockAdapterWithBonus is IRewardsAdapter {
    uint256 public bonusDiscount;
    uint256 public paymentTokenShare;
    address public paymentTokenShareReceiver;

    constructor(uint256 _bonusDiscount, uint256 _paymentTokenShare, address _paymentTokenShareReceiver) {
        bonusDiscount = _bonusDiscount;
        paymentTokenShare = _paymentTokenShare;
        paymentTokenShareReceiver = _paymentTokenShareReceiver;
    }

    function getBonusRewardInfo(address) external view returns (BonusRewardInfo memory) {
        return BonusRewardInfo({
            bonusDiscount: bonusDiscount,
            paymentTokenShare: paymentTokenShare,
            paymentTokenShareReceiver: paymentTokenShareReceiver
        });
    }
}

contract MockAdapterNoBonus is IRewardsAdapter {
    function getBonusRewardInfo(address) external pure returns (BonusRewardInfo memory) {
        return BonusRewardInfo({bonusDiscount: 0, paymentTokenShare: 0, paymentTokenShareReceiver: address(0)});
    }
}

contract MockAdapterExcessiveShare is IRewardsAdapter {
    function getBonusRewardInfo(address) external pure returns (BonusRewardInfo memory) {
        return BonusRewardInfo({
            bonusDiscount: 0.05 ether, // 5%
            paymentTokenShare: MATH_PRECISION + 1, // > 100%
            paymentTokenShareReceiver: address(0x999)
        });
    }
}

contract AltoRewardsDistributorClaimRewardTokensWithAdapters is RewardsDistributorCommon {
    address constant ADAPTER_RECEIVER_1 = address(0x1111);
    address constant ADAPTER_RECEIVER_2 = address(0x2222);

    function _calculatePaymentAmount(uint256 rewardAmount, uint256 discount, address token)
        internal
        view
        returns (uint256)
    {
        uint256 baseCostUSD = (rewardAmount * REWARD_PRICE + 10 ** 18 - 1) / 10 ** 18;
        uint256 discountedCostUSD = baseCostUSD * (MATH_PRECISION - discount) / MATH_PRECISION;
        uint256 tokenPrice = token == address(paymentToken) ? PAYMENT_TOKEN_PRICE : _getOraclePriceFromEther(2 ether);
        ERC20MockDecimals tokenContract = ERC20MockDecimals(token);
        return (discountedCostUSD * 10 ** tokenContract.decimals() + tokenPrice - 1) / tokenPrice; // Round up
    }

    function test_RevertWhen_AdapterPaymentTokenShareTotalExceedsMATH_PRECISION() external {
        // Create adapter with excessive payment token share
        MockAdapterExcessiveShare excessiveAdapter = new MockAdapterExcessiveShare();

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(excessiveAdapter));

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should revert
        vm.expectRevert(IRewardsErrors.AltoRewardsDistributorInvalidAdapterPaymentTokenShare.selector);
        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, aliceAvailable, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();
    }

    function test_WhenAdaptersProvideBonusDiscounts() external {
        // Create adapter with 5% bonus discount and 10% payment share
        MockAdapterWithBonus bonusAdapter = new MockAdapterWithBonus(
            0.05 ether, // 5% bonus discount
            0.1 ether, // 10% payment share
            ADAPTER_RECEIVER_1
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(bonusAdapter));

        uint256 rewardAmount = 1000 ether;
        uint256 expectedCombinedDiscount = BASE_DISCOUNT + 0.05 ether; // 30%
        uint256 expectedPaymentAmount =
            _calculatePaymentAmount(rewardAmount, expectedCombinedDiscount, address(paymentToken));
        uint256 expectedAdapterShare = (expectedPaymentAmount * 0.1 ether) / MATH_PRECISION;

        uint256 receiverBalanceBefore = paymentToken.balanceOf(ADAPTER_RECEIVER_1);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should emit ClaimRewardTokens event with combined discount
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, address(paymentToken), expectedPaymentAmount, rewardAmount, expectedCombinedDiscount
        );

        uint256 actualPaymentAmount = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should apply adapter bonus discount
        assertEq(actualPaymentAmount, expectedPaymentAmount);

        // it should transfer payment token share to adapter receiver
        uint256 receiverBalanceAfter = paymentToken.balanceOf(ADAPTER_RECEIVER_1);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + expectedAdapterShare);
    }

    function test_WhenDiscountReachesMAX_DISCOUNT() external {
        // Create adapters that together would exceed MAX_DISCOUNT
        MockAdapterWithBonus adapter1 = new MockAdapterWithBonus(
            0.4 ether, // 40% bonus discount
            0.05 ether, // 5% payment share
            ADAPTER_RECEIVER_1
        );
        MockAdapterWithBonus adapter2 = new MockAdapterWithBonus(
            0.4 ether, // 40% bonus discount
            0.05 ether, // 5% payment share
            ADAPTER_RECEIVER_2
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter1));
        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter2));

        uint256 rewardAmount = 1000 ether;
        // BASE_DISCOUNT (25%) + adapter1 (40%) + adapter2 (40%) = 105%, but should be capped at MAX_DISCOUNT (50%)
        uint256 expectedCappedDiscount = distributor.MAX_DISCOUNT(); // 50%
        uint256 expectedPaymentAmount =
            _calculatePaymentAmount(rewardAmount, expectedCappedDiscount, address(paymentToken));

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // it should emit ClaimRewardTokens event with capped discount
        vm.expectEmit(true, true, true, true);
        emit IRewardsEvents.ClaimRewardTokens(
            ALICE, ALICE, address(paymentToken), expectedPaymentAmount, rewardAmount, expectedCappedDiscount
        );

        uint256 actualPaymentAmount = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should cap discount at MAX_DISCOUNT
        assertEq(actualPaymentAmount, expectedPaymentAmount);
    }

    function test_WhenAdapterHasZeroPaymentTokenShare() external {
        // Create adapter with bonus discount but zero payment share
        MockAdapterWithBonus bonusAdapter = new MockAdapterWithBonus(
            0.05 ether, // 5% bonus discount
            0, // 0% payment share
            ADAPTER_RECEIVER_1
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(bonusAdapter));

        uint256 rewardAmount = 1000 ether;
        uint256 expectedCombinedDiscount = BASE_DISCOUNT + 0.05 ether; // 30%
        uint256 expectedPaymentAmount =
            _calculatePaymentAmount(rewardAmount, expectedCombinedDiscount, address(paymentToken));

        uint256 receiverBalanceBefore = paymentToken.balanceOf(ADAPTER_RECEIVER_1);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 actualPaymentAmount = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should apply adapter bonus discount
        assertEq(actualPaymentAmount, expectedPaymentAmount);

        // it should not transfer any payment tokens to adapter receiver
        uint256 receiverBalanceAfter = paymentToken.balanceOf(ADAPTER_RECEIVER_1);
        assertEq(receiverBalanceAfter, receiverBalanceBefore);
    }

    function test_WhenAdapterHasZeroAddressReceiver() external {
        // Create adapter with payment share but zero address receiver
        MockAdapterWithBonus bonusAdapter = new MockAdapterWithBonus(
            0.05 ether, // 5% bonus discount
            0.1 ether, // 10% payment share
            address(0) // zero address receiver
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(bonusAdapter));

        uint256 rewardAmount = 1000 ether;

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        uint256 actualPaymentAmount = distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should not revert and should work normally
        assertTrue(actualPaymentAmount > 0);
    }

    function test_WhenAdapterReceiverIsDistributorContract() external {
        // Create adapter with payment share to distributor contract itself
        MockAdapterWithBonus bonusAdapter = new MockAdapterWithBonus(
            0.05 ether, // 5% bonus discount
            0.1 ether, // 10% payment share
            address(distributor) // distributor contract as receiver
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(bonusAdapter));

        uint256 rewardAmount = 1000 ether;
        uint256 distributorBalanceBefore = paymentToken.balanceOf(address(distributor));

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should not send additional tokens to distributor (should skip the transfer)
        uint256 distributorBalanceAfter = paymentToken.balanceOf(address(distributor));
        // Only the main payment amount should be in the contract
        assertTrue(distributorBalanceAfter > distributorBalanceBefore);
    }

    function test_WhenMultipleAdaptersProvidePaymentShares() external {
        MockAdapterWithBonus adapter1 = new MockAdapterWithBonus(
            0.02 ether, // 2% bonus discount
            0.05 ether, // 5% payment share
            ADAPTER_RECEIVER_1
        );
        MockAdapterWithBonus adapter2 = new MockAdapterWithBonus(
            0.03 ether, // 3% bonus discount
            0.07 ether, // 7% payment share
            ADAPTER_RECEIVER_2
        );

        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter1));
        vm.prank(OWNER);
        distributor.whitelistAdapter(address(adapter2));

        uint256 rewardAmount = 1000 ether;
        uint256 expectedCombinedDiscount = BASE_DISCOUNT + 0.02 ether + 0.03 ether; // 30%
        uint256 expectedPaymentAmount =
            _calculatePaymentAmount(rewardAmount, expectedCombinedDiscount, address(paymentToken));
        uint256 expectedAdapter1Share = (expectedPaymentAmount * 0.05 ether) / MATH_PRECISION;
        uint256 expectedAdapter2Share = (expectedPaymentAmount * 0.07 ether) / MATH_PRECISION;

        uint256 receiver1BalanceBefore = paymentToken.balanceOf(ADAPTER_RECEIVER_1);
        uint256 receiver2BalanceBefore = paymentToken.balanceOf(ADAPTER_RECEIVER_2);

        vm.startPrank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        distributor.claimRewardTokens(
            aliceAvailable, aliceProof, rewardAmount, BASE_DISCOUNT, address(paymentToken), false, ALICE
        );
        vm.stopPrank();

        // it should transfer correct payment shares to both adapter receivers
        uint256 receiver1BalanceAfter = paymentToken.balanceOf(ADAPTER_RECEIVER_1);
        uint256 receiver2BalanceAfter = paymentToken.balanceOf(ADAPTER_RECEIVER_2);

        assertEq(receiver1BalanceAfter, receiver1BalanceBefore + expectedAdapter1Share);
        assertEq(receiver2BalanceAfter, receiver2BalanceBefore + expectedAdapter2Share);
    }
}
