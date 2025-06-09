// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";

contract ClaimInterestTest is AltoMintMarketTest {
    function test_NotTransferTokensWhen_ClaimableFeesIsZero() external {
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(feeRecipient);

        market.claimInterest();

        // it should not transfer tokens
        uint256 feeRecipientBalanceAfter = borrowToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalanceAfter, feeRecipientBalanceBefore);
        assertEq(market.claimableFeesAssets(), 0);
    }

    modifier givenClaimableFeesIsGreaterThanZero() {
        // Setup to generate claimable fees
        vm.startPrank(alice);
        market.addCollateral(500 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Advance time to accrue interest
        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();
        _;
    }

    function test_MintTokensToFeeRecipientWhen_ClaimableFeesIsGreaterThanZero()
        external
        givenClaimableFeesIsGreaterThanZero
    {
        uint256 claimableFeesBeforeAmount = market.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(feeRecipient);

        market.claimInterest();

        // it should mint tokens to fee recipient
        uint256 feeRecipientBalanceAfter = borrowToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalanceAfter, feeRecipientBalanceBefore + claimableFeesBeforeAmount);
        assertEq(market.claimableFeesAssets(), 0);
    }
}
