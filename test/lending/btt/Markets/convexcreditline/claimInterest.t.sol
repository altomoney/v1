// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {ILendingOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketClaimInterestTest is ConvexCreditLineCommon {
    function test_RevertWhenPaused() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        vm.prank(OWNER);
        market.claimInterest(0);
    }

    function test_FeeRecipientCheckPrecedesAmountCheck() external {
        vm.store(address(market), bytes32(uint256(13)), bytes32(0));
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.claimInterest(1);

        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.claimInterest(0);
    }

    function test_AnyoneCanClaimFeesOnlyForConfiguredRecipients() external {
        _createFees(10 ether);
        uint256 callerBalanceBefore = borrowToken.balanceOf(USER);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 2.8 ether);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(REWARD_RECIPIENT, 1.2 ether);
        vm.prank(USER);
        uint256 claimed = market.claimInterest(4 ether);
        assertEq(claimed, 4 ether);
        assertEq(market.claimableFeesAssets(), 6 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 2.8 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 1.2 ether);
        assertEq(borrowToken.balanceOf(USER), callerBalanceBefore);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 4.2 ether);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(REWARD_RECIPIENT, 1.8 ether);
        vm.prank(USER);
        claimed = market.claimInterest(0);
        assertEq(claimed, 6 ether);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(borrowToken.balanceOf(USER), callerBalanceBefore);

        _assertEmptyClaim(USER);
    }

    function test_OverclaimsRevertWithInvalidInputWithoutMintingOrChangingAccounting() external {
        _createFees(10 ether);
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        uint256 recipientBalanceBefore = borrowToken.balanceOf(FEE_RECIPIENT);
        uint256 treasuryBalanceBefore = borrowToken.balanceOf(REWARD_RECIPIENT);

        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.claimInterest(10 ether + 1);
        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), recipientBalanceBefore);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), treasuryBalanceBefore);

        vm.prank(FEE_RECIPIENT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.claimInterest(uint256(type(uint128).max) + 1);
        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), recipientBalanceBefore);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), treasuryBalanceBefore);

        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.claimInterest(type(uint256).max);
        _assertUnchanged(beforeState);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), recipientBalanceBefore);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), treasuryBalanceBefore);
    }

    function test_ZeroClaimsAllAndEmptyBalanceSkipsMintingAndEvents() external {
        _createFees(10 ether);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(FEE_RECIPIENT, 7 ether);
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.InterestClaimed(REWARD_RECIPIENT, 3 ether);
        vm.prank(FEE_RECIPIENT);
        uint256 claimed = market.claimInterest(0);
        assertEq(claimed, 10 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(market.claimableFeesAssets(), 0);

        _assertEmptyClaim(OWNER);
    }

    function test_OwnerCanClaimAllWithZeroAmount() external {
        _createFees(10 ether);

        vm.prank(OWNER);
        uint256 claimed = market.claimInterest(0);

        assertEq(claimed, 10 ether);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
    }

    function test_OwnerCanClaimExactFullAmount() external {
        _createFees(10 ether);

        vm.prank(OWNER);
        uint256 claimed = market.claimInterest(10 ether);

        assertEq(claimed, 10 ether);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
    }

    function test_FeeRecipientEmptyClaimReturnsZeroWithoutMintingOrEvents() external {
        _assertEmptyClaim(FEE_RECIPIENT);
        assertEq(market.claimableFeesAssets(), 0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
    }

    function test_FeeRecipientCanPartiallyClaimAndPreserveRemainder() external {
        _createFees(10 ether);

        vm.prank(FEE_RECIPIENT);
        uint256 claimed = market.claimInterest(4 ether);

        assertEq(claimed, 4 ether);
        assertEq(market.claimableFeesAssets(), 6 ether);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 2.8 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 1.2 ether);
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
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
    }

    function test_ClaimDoesNotAccrueOrTouchMarketOrConvexAccounting() external {
        _createFees(10 ether);
        AccountingState memory beforeState = _state();
        uint256 deposits = booster.depositCalls();
        uint256 withdrawals = rewardPool.withdrawCalls();
        uint256 rewardClaims = rewardPool.getRewardCalls();
        _mockIrmUpdateRevert();
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");
        booster.setDepositBehavior(true, true, type(uint256).max, type(uint256).max);
        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        rewardPool.setRewardBehavior(true, true);

        vm.prank(OWNER);
        market.claimInterest(4 ether);
        vm.clearMockedCalls();

        beforeState.claimableFees -= uint128(4 ether);
        _assertUnchanged(beforeState);
        assertEq(booster.depositCalls(), deposits);
        assertEq(rewardPool.withdrawCalls(), withdrawals);
        assertEq(rewardPool.getRewardCalls(), rewardClaims);
    }

    function test_AccruedInterestAndOpeningFeesShareOneClaimableBalance() external {
        _createFees(10 ether);
        _mockAccrual(5 ether, 1);
        market.accrueInterest();
        assertEq(market.claimableFeesAssets(), 15 ether);

        vm.prank(FEE_RECIPIENT);
        market.claimInterest(0);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 10.5 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 4.5 ether);
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
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(market.badDebtAssets(), badDebt);
    }

    function test_ZeroTreasuryShareMintsAndEmitsOnlyForFeeRecipient() external {
        _createFees(10 ether);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(0);
        vm.mockCallRevert(
            address(borrowToken), abi.encodeWithSelector(borrowToken.mint.selector, REWARD_RECIPIENT), "ZERO_MINT"
        );

        vm.expectEmit(address(market));
        emit InterestClaimed(FEE_RECIPIENT, 10 ether);
        vm.recordLogs();
        assertEq(market.claimInterest(0), 10 ether);
        _assertClaimEventCount(vm.getRecordedLogs(), 1);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 10 ether);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
    }

    function test_FullTreasuryShareMintsAndEmitsOnlyForRewardRecipient() external {
        _createFees(10 ether);
        vm.prank(OWNER);
        market.setTreasuryInterestBps(10_000);
        vm.mockCallRevert(
            address(borrowToken), abi.encodeWithSelector(borrowToken.mint.selector, FEE_RECIPIENT), "ZERO_MINT"
        );

        vm.expectEmit(address(market));
        emit InterestClaimed(REWARD_RECIPIENT, 10 ether);
        vm.recordLogs();
        assertEq(market.claimInterest(0), 10 ether);
        _assertClaimEventCount(vm.getRecordedLogs(), 1);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 10 ether);
    }

    function test_RoundsUpTreasuryShareAndPreservesTotalClaimed() external {
        _createFees(10 ether);
        uint256 supplyBefore = borrowToken.totalSupply();
        vm.expectEmit(address(market));
        emit InterestClaimed(FEE_RECIPIENT, 7);
        vm.expectEmit(address(market));
        emit InterestClaimed(REWARD_RECIPIENT, 4);

        vm.recordLogs();
        uint256 claimed = market.claimInterest(11);

        _assertClaimEventCount(vm.getRecordedLogs(), 2);
        assertEq(claimed, 11);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 7);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 4);
        assertEq(borrowToken.totalSupply() - supplyBefore, claimed);
        assertEq(market.claimableFeesAssets(), 10 ether - claimed);
    }

    function test_OneWeiClaimGoesEntirelyToTreasuryWithoutZeroMintOrEvent() external {
        _createFees(10 ether);
        vm.mockCallRevert(
            address(borrowToken), abi.encodeWithSelector(borrowToken.mint.selector, FEE_RECIPIENT), "ZERO_MINT"
        );
        vm.expectEmit(address(market));
        emit InterestClaimed(REWARD_RECIPIENT, 1);

        vm.recordLogs();
        assertEq(market.claimInterest(1), 1);

        _assertClaimEventCount(vm.getRecordedLogs(), 1);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 1);
        assertEq(market.claimableFeesAssets(), 10 ether - 1);
    }

    function test_MatchingRecipientsReceiveExactlyTheTotalClaim() external {
        _createFees(10 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.setRewardRecipient(FEE_RECIPIENT);
        uint256 supplyBefore = borrowToken.totalSupply();
        vm.expectEmit(address(market));
        emit InterestClaimed(FEE_RECIPIENT, 7 ether);
        vm.expectEmit(address(market));
        emit InterestClaimed(FEE_RECIPIENT, 3 ether);

        vm.recordLogs();
        assertEq(market.claimInterest(0), 10 ether);

        _assertClaimEventCount(vm.getRecordedLogs(), 2);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 10 ether);
        assertEq(borrowToken.totalSupply() - supplyBefore, 10 ether);
        assertEq(market.claimableFeesAssets(), 0);
    }

    function test_FeeRecipientMintFailureRollsBackBothSharesAndAccounting() external {
        _assertMintFailureRollsBack(false);
    }

    function test_TreasuryMintFailureRollsBackBothSharesAndAccounting() external {
        _assertMintFailureRollsBack(true);
    }

    function _assertMintFailureRollsBack(bool failTreasury) private {
        _createFees(10 ether);
        AccountingState memory beforeState = _state();
        uint256 supplyBefore = borrowToken.totalSupply();
        (uint256 mintedBefore,) = borrowToken.minterConfig(address(market));
        if (failTreasury) {
            vm.expectCall(address(borrowToken), abi.encodeCall(borrowToken.mint, (FEE_RECIPIENT, 7 ether)));
        }
        vm.mockCallRevert(
            address(borrowToken),
            abi.encodeCall(
                borrowToken.mint, (failTreasury ? REWARD_RECIPIENT : FEE_RECIPIENT, failTreasury ? 3 ether : 7 ether)
            ),
            "MINT_REVERTED"
        );

        vm.expectRevert(bytes("MINT_REVERTED"));
        market.claimInterest(0);

        _assertUnchanged(beforeState);
        assertEq(borrowToken.balanceOf(FEE_RECIPIENT), 0);
        assertEq(borrowToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        (uint256 mintedAfter,) = borrowToken.minterConfig(address(market));
        assertEq(mintedAfter, mintedBefore);
    }

    function test_MaximumClaimConservesAssetsAndRoundsTowardTreasury() external {
        _assertClaimConservesAssets(type(uint128).max, type(uint128).max, TREASURY_INTEREST_BPS);
    }

    function test_PartialClaimWithMinimumTreasuryShareConservesAssets() external {
        _assertClaimConservesAssets(type(uint128).max, type(uint128).max - 1, 1);
    }

    function test_PartialClaimWithNearFullTreasuryShareConservesAssets() external {
        _assertClaimConservesAssets(type(uint128).max, type(uint128).max - 1, market.PERCENTAGE_PRECISION() - 1);
    }

    function _assertClaimConservesAssets(uint128 fees, uint256 amount, uint256 bps) private {
        vm.prank(OWNER);
        market.setTreasuryInterestBps(bps);
        _mockAccrual(fees, 1);
        market.accrueInterest();

        uint256 claimed = market.claimInterest(amount);

        uint256 treasuryAmount = borrowToken.balanceOf(REWARD_RECIPIENT);
        uint256 feeRecipientAmount = borrowToken.balanceOf(FEE_RECIPIENT);
        assertEq(claimed, amount);
        assertEq(treasuryAmount + feeRecipientAmount, claimed);
        assertEq(borrowToken.totalSupply(), claimed);
        assertEq(market.claimableFeesAssets(), uint256(fees) - claimed);
        uint256 precision = market.PERCENTAGE_PRECISION();
        assertGe(treasuryAmount * precision, claimed * bps);
        assertLt(treasuryAmount * precision, claimed * bps + precision);
    }

    function _assertEmptyClaim(address caller) private {
        uint256 supplyBefore = borrowToken.totalSupply();
        vm.mockCallRevert(address(borrowToken), borrowToken.mint.selector, "ZERO_MINT");
        vm.recordLogs();
        vm.prank(caller);
        assertEq(market.claimInterest(0), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        assertEq(borrowToken.totalSupply(), supplyBefore);
        vm.clearMockedCalls();
    }

    function _assertClaimEventCount(Vm.Log[] memory logs, uint256 expected) private view {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(market) && logs[i].topics[0] == InterestClaimed.selector) ++count;
        }
        assertEq(count, expected);
    }

    function _createFees(uint256 expectedFee) private {
        _setOpeningFee(0.1 ether);
        _openPosition(1_000 ether, 100 ether);
        assertEq(market.claimableFeesAssets(), expectedFee);
    }
}
