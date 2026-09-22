// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketRemoveCollateralTest is ConvexCreditLineCommon {
    function test_RevertWhenPausedButRemainAvailableWhenFrozen() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");

        _unpause(PAUSE_TYPE);
        _pause(FROZEN_TYPE);
        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_CreditInputChecksHaveSpecifiedPrecedence() external {
        _openPosition(100 ether, 10 ether);

        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.removeCollateral(0, USER, address(0), hex"01");
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketCallbacksUnsupported.selector);
        market.removeCollateral(0, USER, RECEIVER, hex"01");
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.removeCollateral(0, USER, RECEIVER, "");
    }

    function test_BaseAmountAuthorizationAndRecordedBalanceChecks() external {
        _addCollateral(10 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInvalidInput.selector);
        market.removeCollateral(0, CREDIT_ACCOUNT, RECEIVER, "");

        vm.prank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.removeCollateral(1, CREDIT_ACCOUNT, RECEIVER, "");

        AccountingState memory beforeState = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert();
        market.removeCollateral(11 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function test_ActiveWithdrawalExternalFailuresAreAtomic() external {
        _addCollateral(30 ether);
        AccountingState memory beforeState = _state();

        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("WITHDRAW_REVERTED"));
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function test_InactiveWithdrawalTransfersRecoveredCollateralWithoutCallingConvexAndPreservesSurplus() external {
        _addCollateral(10 ether);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        deal(address(collateralToken), address(market), 13 ether);
        uint256 callsBefore = rewardPool.withdrawCalls();

        vm.recordLogs();
        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");

        assertEq(assets, 10 ether);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, 0);
        assertEq(collateralToken.balanceOf(RECEIVER), 10 ether);
        assertEq(collateralToken.balanceOf(address(market)), 3 ether);
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
        _assertNoCollateralUnstakedEvent();
    }

    function test_InactiveWithdrawalWithInsufficientIdleCollateralRevertsAtomically() external {
        _addCollateral(10 ether);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        deal(address(collateralToken), address(market), 9 ether);
        AccountingState memory beforeState = _state();
        uint256 callsBefore = rewardPool.withdrawCalls();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(market), 9 ether, 10 ether)
        );
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(RECEIVER), 0);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
    }

    function test_ReceiverTransferFailureRestoresActiveCustodyAndAccounting() external {
        _addCollateral(10 ether);
        vm.mockCallRevert(
            address(collateralToken),
            abi.encodeCall(collateralToken.transfer, (RECEIVER, 1 ether)),
            bytes("TRANSFER_REVERTED")
        );
        AccountingState memory beforeState = _state();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("TRANSFER_REVERTED"));
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();

        _assertUnchanged(beforeState);
    }

    function test_DebtFreeWithdrawalSkipsOracleButAccruesBeforeCustody() external {
        _addCollateral(10 ether);
        AccountingState memory beforeState = _state();
        uint256 depositsBefore = booster.depositCalls();
        uint256 rewardClaimsBefore = rewardPool.getRewardCalls();
        _mockAccrual(0, 29);
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.CollateralUnstaked(RECEIVER, 10 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.RemoveCollateral(CREDIT_ACCOUNT, CREDIT_ACCOUNT, RECEIVER, 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();

        assertEq(assets, 10 ether);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, 0);
        assertEq(collateralToken.balanceOf(RECEIVER), 10 ether);
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(rewardPool.lastWithdrawAmount(), 10 ether);
        assertFalse(rewardPool.lastWithdrawClaim());
        (uint128 supplyAssets, uint128 supplyShares) = market.totalSupply();
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(supplyAssets, beforeState.totalSupply.assets);
        assertEq(supplyShares, beforeState.totalSupply.shares);
        assertEq(debtAssets, beforeState.totalBorrowed.assets);
        assertEq(debtShares, beforeState.totalBorrowed.shares);
        assertEq(market.claimableFeesAssets(), beforeState.claimableFees);
        assertEq(booster.depositCalls(), depositsBefore);
        assertEq(rewardPool.getRewardCalls(), rewardClaimsBefore);
    }

    function test_PartialWithdrawalWithDebtSucceedsWhileRemainingPositionIsSolvent() external {
        _openPosition(100 ether, 50 ether);
        _mockAccrual(0, 1);
        (, uint128 borrowSharesBefore,) = market.position(CREDIT_ACCOUNT);
        (uint128 debtAssetsBefore, uint128 debtSharesBefore) = market.totalBorrowed();

        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(20 ether, CREDIT_ACCOUNT, RECEIVER, "");

        (uint128 debtAssetsAfter, uint128 debtSharesAfter) = market.totalBorrowed();
        (, uint128 borrowSharesAfter, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(assets, 20 ether);
        assertEq(collateralAfter, 80 ether);
        assertEq(borrowSharesAfter, borrowSharesBefore);
        assertEq(debtAssetsAfter, debtAssetsBefore);
        assertEq(debtSharesAfter, debtSharesBefore);
        assertEq(collateralToken.balanceOf(RECEIVER), 20 ether);
        assertEq(rewardPool.balanceOf(address(market)), 80 ether);
    }

    function test_WithdrawalSucceedsWhenRemainingPositionIsExactlyAtMaxLtv() external {
        _openPosition(100 ether, 60 ether);
        _mockAccrual(0, 1);

        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(20 ether, CREDIT_ACCOUNT, RECEIVER, "");

        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        (, uint128 positionShares, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(assets, 20 ether);
        assertEq(debtAssets, 60 ether);
        assertEq(collateralAfter, 80 ether);
        assertEq(uint256(collateralAfter) * MAX_LTV / 1 ether, debtAssets);
        assertEq(positionShares, debtShares);
        assertEq(collateralToken.balanceOf(RECEIVER), 20 ether);
        assertEq(rewardPool.balanceOf(address(market)), 80 ether);
    }

    function test_PartialWithdrawalThatWouldMakePositionInsolventRevertsAtomically() external {
        _openPosition(100 ether, 50 ether);
        _mockAccrual(0, 1);
        AccountingState memory beforeState = _state();
        uint256 receiverBalanceBefore = collateralToken.balanceOf(RECEIVER);

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientUserCollateral.selector);
        market.removeCollateral(40 ether, CREDIT_ACCOUNT, RECEIVER, "");

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(RECEIVER), receiverBalanceBefore);
    }

    function test_DebtedWithdrawalRequiresValidOracleAndRevertsAtomically() external {
        _openPosition(100 ether, 50 ether);
        _mockAccrual(0, 1);
        AccountingState memory beforeState = _state();

        oracle.setPrice(0);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidOraclePrice.selector);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_REVERTED");
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("ORACLE_REVERTED"));
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();
        _assertUnchanged(beforeState);
    }

    function test_AuthorizedDelegateCanWithdrawAndUnrelatedCallerCannot() external {
        _addCollateral(10 ether);
        vm.prank(DELEGATE);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");

        vm.prank(USER);
        vm.expectRevert(IMarketErrors.AltoBaseMarketUnauthorized.selector);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_ResidualGlobalDebtDoesNotBlockDebtFreePositionWithdrawal() external {
        _openPosition(10 ether, 1);
        _mockAccrual(1 ether, 1);
        market.accrueInterest();
        _mockAccrual(0, 1);
        (, uint128 positionShares,) = market.position(CREDIT_ACCOUNT);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        uint256 numerator = uint256(positionShares) * (uint256(debtAssets) + 1);
        uint256 denominator = uint256(debtShares) + 1e6;
        uint256 burnAssets = numerator / denominator;
        if (numerator % denominator != 0) ++burnAssets;
        deal(address(borrowToken), CREDIT_ACCOUNT, burnAssets);
        vm.prank(CREDIT_ACCOUNT);
        market.repay(0, positionShares, CREDIT_ACCOUNT);
        (debtAssets,) = market.totalBorrowed();
        assertGt(debtAssets, 0);

        oracle.setPrice(0);
        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");
        assertEq(collateralToken.balanceOf(RECEIVER), 1 ether);
    }

    function test_IrmFailurePrecedesAccountingAndConvexWithdrawal() external {
        _addCollateral(10 ether);
        _mockIrmUpdateRevert();
        AccountingState memory beforeState = _state();
        uint256 callsBefore = rewardPool.withdrawCalls();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");

        _assertUnchanged(beforeState);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
    }
}
