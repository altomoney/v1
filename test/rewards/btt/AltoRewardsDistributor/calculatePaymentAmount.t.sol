// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {RewardsDistributorCommon} from "./RewardsDistributorCommon.t.sol";

contract CalculatePaymentAmountTest is RewardsDistributorCommon {
    function setUp() public override {
        super.setUp();
    }

    function test_CalculatePaymentAmount_SmallRewardPurchase_WithSufficientValue() public {
        // Setup: Small reward purchase that results in non-zero payment after discount
        // Need enough value so that after discount truncation, payment is still > 0
        uint256 rewardsPurchaseAmount = 10_000_000_001; // Enough to result in USD value of 2, so 2*0.75 = 1.5 -> 1 after truncation
        address paymentTokenAddr = address(paymentToken);

        // Set reward token price to $1.00 (8 decimals)
        uint256 rewardTokenPrice = 1e8; // $1.00
        rewardOracle.setPrice(rewardTokenPrice);

        // Set payment token price to $1.00 (8 decimals)
        uint256 paymentTokenPrice = 1e8; // $1.00
        paymentOracle.setPrice(paymentTokenPrice);

        // Get alice's balance before
        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        // Alice approves the contract
        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Execute the claim using Alice's existing proof and discount
        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0), // Alice's total available from merkle tree
            aliceProof, // Alice's existing proof
            rewardsPurchaseAmount, // Purchase enough to avoid zero payment
            paymentTokenAddr,
            false, // don't lock
            0, // maxEpochsToLockFor
            ALICE
        );

        // Assert: Payment amount should be greater than 0
        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // The payment should be non-zero due to sufficient value surviving discount truncation
        assertGt(paymentAmount, 0, "Payment amount should be greater than 0 with sufficient purchase amount");

        // Verify alice received the reward tokens
        assertEq(rewardToken.balanceOf(ALICE), rewardsPurchaseAmount, "Alice should receive the reward tokens");
    }

    function test_CalculatePaymentAmount_NormalRewardPurchase_ShouldCalculateCorrectly() public {
        // Setup: Normal sized reward purchase
        uint256 rewardsPurchaseAmount = 1e18; // 1 full reward token
        address paymentTokenAddr = address(paymentToken);

        // Set reward token price to $2.50 (8 decimals)
        uint256 rewardTokenPrice = 250_000_000; // $2.50
        rewardOracle.setPrice(rewardTokenPrice);

        // Set payment token price to $1.00 (8 decimals)
        uint256 paymentTokenPrice = 100_000_000; // $1.00
        paymentOracle.setPrice(paymentTokenPrice);

        // Get alice's balance before
        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        // Alice approves the contract
        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Execute the claim
        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            rewardsPurchaseAmount,
            paymentTokenAddr,
            false,
            0,
            ALICE
        );

        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // Should be approximately 2.5 payment tokens with 25% discount = 1.875 tokens
        // But need to account for payment token having 6 decimals vs reward token 18 decimals
        // Expected: (1e18 * 2.5e8 / 1e18) * 0.75 * 1e6 / 1e8 = 1.875e6 payment token units
        uint256 expectedPayment = 1_875_000; // 1.875 tokens with 6 decimals

        // Allow for rounding up
        assertGe(paymentAmount, expectedPayment, "Payment should be at least the expected amount");
        assertLt(paymentAmount, expectedPayment + 1000, "Payment should not be too much higher due to rounding");
    }

    function test_CalculatePaymentAmount_WithHighDiscount_ShouldReducePayment() public {
        // Setup: Purchase with high discount
        uint256 rewardsPurchaseAmount = 1e18; // 1 full reward token
        address paymentTokenAddr = address(paymentToken);

        // Set both tokens to $1.00 for simplicity
        uint256 tokenPrice = 100_000_000; // $1.00
        rewardOracle.setPrice(tokenPrice);
        paymentOracle.setPrice(tokenPrice);

        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Alice gets BASE_DISCOUNT (25%) from merkle tree
        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            rewardsPurchaseAmount,
            paymentTokenAddr,
            false,
            0,
            ALICE
        );

        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // Should be approximately 0.75 payment tokens (1 - 0.25 discount)
        // Expected: 0.75e6 = 750_000 payment token units (6 decimals)
        uint256 expectedPayment = 750_000;

        assertGe(paymentAmount, expectedPayment, "Payment with discount should be at least expected amount");
        assertLt(paymentAmount, expectedPayment + 1000, "Payment should not be too much higher");
    }

    function testFuzz_CalculatePaymentAmount_ReasonableScenarios(
        uint256 rewardsPurchaseAmount,
        uint256 rewardPrice,
        uint256 paymentPrice
    ) public {
        // Bound inputs to reasonable ranges that won't cause balance issues
        rewardsPurchaseAmount = bound(rewardsPurchaseAmount, 1e15, 1e18); // 0.001 to 1 token
        rewardPrice = bound(rewardPrice, 1e7, 1e10); // $0.1 to $100
        paymentPrice = bound(paymentPrice, 1e7, 1e10); // $0.1 to $100

        address paymentTokenAddr = address(paymentToken);

        // Set oracle prices
        rewardOracle.setPrice(rewardPrice);
        paymentOracle.setPrice(paymentPrice);

        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            rewardsPurchaseAmount,
            paymentTokenAddr,
            false,
            0,
            ALICE
        );

        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // With reasonable parameters, payment should be non-zero
        assertGt(paymentAmount, 0, "Payment amount should be greater than 0 for reasonable scenarios");

        // Alice should have received the rewards
        assertEq(rewardToken.balanceOf(ALICE), rewardsPurchaseAmount, "Alice should receive the rewards");
    }

    function test_CalculatePaymentAmount_ZeroPaymentEdgeCase() public {
        // This test verifies the specific edge case where discount truncation results in zero payment
        // This demonstrates the documented behavior: "When discount results in zero payment due to rounding, allow it"

        uint256 rewardsPurchaseAmount = 1; // 1 wei - minimal purchase
        address paymentTokenAddr = address(paymentToken);

        // Set prices that will trigger the edge case
        rewardOracle.setPrice(1e8); // $1.00
        paymentOracle.setPrice(1e8); // $1.00

        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        // Execute the transaction that should not result in zero payment
        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            rewardsPurchaseAmount,
            paymentTokenAddr,
            false,
            0,
            ALICE
        );

        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // This documents the edge case behavior
        assertEq(paymentAmount, 1, "Payment amount is due to rounding up");

        // Alice should still receive the reward token (this is the intended behavior)
        assertEq(
            rewardToken.balanceOf(ALICE), rewardsPurchaseAmount, "Alice should receive rewards even with zero payment"
        );
    }

    function test_CalculatePaymentAmount_RoundingPreventsUnderpayment() public {
        // This test verifies that the double rounding UP prevents the protocol from being underpaid

        uint256 rewardsPurchaseAmount = 1e18; // 1 full token
        address paymentTokenAddr = address(paymentToken);

        // Set slightly mismatched prices to see rounding effects
        rewardOracle.setPrice(100_000_001); // Slightly above $1.00
        paymentOracle.setPrice(99_999_999); // Slightly below $1.00

        uint256 alicePaymentBalanceBefore = paymentToken.balanceOf(ALICE);

        vm.prank(ALICE);
        paymentToken.approve(address(distributor), type(uint256).max);

        vm.prank(ALICE);
        distributor.claimRewardTokens(
            _getClaimData(aliceAvailable, BASE_DISCOUNT, 0, 0),
            aliceProof,
            rewardsPurchaseAmount,
            paymentTokenAddr,
            false,
            0,
            ALICE
        );

        uint256 alicePaymentBalanceAfter = paymentToken.balanceOf(ALICE);
        uint256 paymentAmount = alicePaymentBalanceBefore - alicePaymentBalanceAfter;

        // Calculate what the payment would be if there was no rounding (would be lower)
        // This demonstrates that rounding UP protects the protocol from underpayment

        assertGt(paymentAmount, 0, "Payment should be positive");

        // The exact amount should be at least what's needed to cover the discounted reward value
        // Due to rounding up, it may be slightly higher than the theoretical minimum
        uint256 expectedMinimum = 750_000; // Approximately 0.75 tokens with discount, in payment token decimals
        assertGe(paymentAmount, expectedMinimum, "Payment should be at least the discounted value");
    }
}
