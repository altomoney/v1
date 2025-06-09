// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoMintMarketTest} from "./AltoMintMarket.t.sol";

contract ClaimInterestTest is AltoMintMarketTest {
    modifier givenClaimableFeesAssetsIsZero() {
        // Default state - no fees accumulated
        _;
    }

    function test_GivenClaimableFeesAssetsIsZero() external givenClaimableFeesAssetsIsZero {
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(feeRecipient);

        market.claimInterest();

        // it should mint zero tokens to feeRecipient
        uint256 feeRecipientBalanceAfter = borrowToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalanceAfter, feeRecipientBalanceBefore);

        // it should set claimableFeesAssets to zero
        assertEq(market.claimableFeesAssets(), 0);
    }

    modifier givenClaimableFeesAssetsIsGreaterThanZero() {
        // Simulate some borrowed assets to generate interest
        vm.startPrank(alice);
        market.addCollateral(200 ether, alice);
        market.borrow(100 ether, 0, alice, alice, "");
        vm.stopPrank();

        // Advance time to accrue interest
        vm.warp(block.timestamp + 365 days);
        market.accrueInterest();
        _;
    }

    function test_GivenClaimableFeesAssetsIsGreaterThanZero() external givenClaimableFeesAssetsIsGreaterThanZero {
        uint256 claimableFeesBeforeAmount = market.claimableFeesAssets();
        uint256 feeRecipientBalanceBefore = borrowToken.balanceOf(feeRecipient);

        market.claimInterest();

        // it should mint claimableFeesAssets amount to feeRecipient
        uint256 feeRecipientBalanceAfter = borrowToken.balanceOf(feeRecipient);
        assertEq(feeRecipientBalanceAfter, feeRecipientBalanceBefore + claimableFeesBeforeAmount);

        // it should set claimableFeesAssets to zero
        assertEq(market.claimableFeesAssets(), 0);
    }
}
