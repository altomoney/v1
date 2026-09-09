// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketClaimInterestTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedButRemainAvailableWhenFrozen() external {
        _createFees(10 ether);
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        vm.prank(OWNER);
        market.claimInterest(0);

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.claimInterest(0);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_AmountCheckPrecedesFeeRecipientAndCallerChecks() external {
        vm.store(address(market), bytes32(uint256(13)), bytes32(0));
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.claimInterest(1);

        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.claimInterest(0);
    }

    function test_RevertWhenCallerIsNeitherOwnerNorFeeRecipient() external {
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.claimInterest(0);
    }

    function test_ZeroClaimsAllAndZeroBalanceEmitsWithoutMinting() external {
        _createFees(10 ether);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 10 ether);
        vm.prank(FEE_RECIPIENT);
        uint256 claimed = market.claimInterest(0);
        assertEq(claimed, 10 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 10 ether);
        assertEq(market.claimableFeesAssets(), 0);

        uint256 supplyBefore = borrowToken.totalSupply();
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 0);
        vm.prank(OWNER);
        claimed = market.claimInterest(0);
        assertEq(claimed, 0);
        assertEq(borrowToken.totalSupply(), supplyBefore);
    }

    function test_OwnerAndFeeRecipientCanPartiallyAndFullyClaim() external {
        _createFees(10 ether);
        vm.prank(OWNER);
        uint256 claimed = market.claimInterest(4 ether);
        assertEq(claimed, 4 ether);
        assertEq(market.claimableFeesAssets(), 6 ether);

        vm.prank(FEE_RECIPIENT);
        claimed = market.claimInterest(6 ether);
        assertEq(claimed, 6 ether);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 10 ether);
    }

    function test_MintFailureAndReentrancyPreserveClaimableBalance() external {
        _createFees(10 ether);
        AccountingState memory beforeState = _state();
        borrowToken.setMintBurnFailure(true, false);

        vm.prank(OWNER);
        vm.expectRevert(bytes("MINT_REVERTED"));
        market.claimInterest(4 ether);
        _assertUnchanged(beforeState);

        borrowToken.setMintBurnFailure(false, false);
        borrowToken.setCallback(address(market), abi.encodeCall(market.claimInterest, (1)), 1);
        vm.prank(OWNER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.claimInterest(4 ether);
        _assertUnchanged(beforeState);
    }

    function test_ClaimDoesNotAccrueOrTouchMarketOrConvexAccounting() external {
        _createFees(10 ether);
        AccountingState memory beforeState = _state();
        uint256 deposits = booster.depositCalls();
        uint256 withdrawals = rewardPool.withdrawCalls();
        _mockIrmUpdateRevert();

        vm.prank(OWNER);
        market.claimInterest(4 ether);

        AccountingState memory afterState = _state();
        assertEq(afterState.totalSupply.assets, beforeState.totalSupply.assets);
        assertEq(afterState.totalBorrowed.assets, beforeState.totalBorrowed.assets);
        assertEq(afterState.totalBorrowed.shares, beforeState.totalBorrowed.shares);
        assertEq(afterState.creditPosition.borrowShares, beforeState.creditPosition.borrowShares);
        assertEq(afterState.creditPosition.collateralAssets, beforeState.creditPosition.collateralAssets);
        assertEq(afterState.claimableFees, beforeState.claimableFees - 4 ether);
        assertEq(booster.depositCalls(), deposits);
        assertEq(rewardPool.withdrawCalls(), withdrawals);
    }

    function test_AccruedInterestAndOpeningFeesShareOneClaimableBalance() external {
        _createFees(10 ether);
        _mockAccrual(5 ether, 1);
        market.accrueInterest();
        assertEq(market.claimableFeesAssets(), 15 ether);

        vm.prank(FEE_RECIPIENT);
        market.claimInterest(0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 15 ether);
    }

    function test_FeesRemainClaimableAfterGovernanceForeclosure() external {
        _createFees(10 ether);
        uint256 fees = market.claimableFeesAssets();
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(market.claimableFeesAssets(), fees);
        uint256 badDebt = market.badDebtAssets();
        assertEq(badDebt, 110 ether);
        vm.prank(FEE_RECIPIENT);
        market.claimInterest(0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), fees);
        assertEq(market.badDebtAssets(), badDebt);
    }

    function _createFees(uint256 expectedFee) private {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        assertEq(market.claimableFeesAssets(), expectedFee);
    }
}
