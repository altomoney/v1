// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {
    IAltoConvexCreditLineErrors,
    IAltoConvexCreditLineEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
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

        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketZeroAddress.selector);
        market.removeCollateral(0, USER, address(0), hex"01");
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketCallbacksUnsupported.selector);
        market.removeCollateral(0, USER, RECEIVER, hex"01");
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
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
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function test_ActiveWithdrawalRequiresExactNonnegativeRawLpDelta() external {
        _addCollateral(30 ether);
        AccountingState memory beforeState = _state();

        rewardPool.setWithdrawBehavior(false, true, 9 ether, 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        deal(address(collateralToken), address(rewardPool), 40 ether);
        rewardPool.setWithdrawBehavior(false, true, 11 ether, 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        deal(address(collateralToken), address(market), 1 ether);
        rewardPool.setWithdrawBehavior(false, true, 1 ether, 10 ether);
        collateralToken.setTransferBehavior(false, false, 10_000, 2 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert();
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
    }

    function test_InactiveWithdrawalUsesIdleOnlyAndRequiresCoverage() external {
        _addCollateral(10 ether);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        uint256 callsBefore = rewardPool.withdrawCalls();

        deal(address(collateralToken), address(market), 5 ether);
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");

        deal(address(collateralToken), address(market), 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        assertEq(collateralToken.balanceOf(RECEIVER), 10 ether);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
    }

    function test_ReceiverTransferFailureRestoresInactiveCustodyAndAccounting() external {
        _addCollateral(10 ether);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        collateralToken.setTransferBehavior(true, false, 10_000, 0);
        AccountingState memory beforeState = _state();

        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(bytes("TRANSFER_REVERTED"));
        market.removeCollateral(1 ether, CREDIT_ACCOUNT, RECEIVER, "");

        _assertUnchanged(beforeState);
    }

    function test_DebtFreeWithdrawalSkipsOracleButAccruesBeforeCustody() external {
        _addCollateral(10 ether);
        _mockAccrual(0, 29);
        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(29, 0, 0, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.CollateralUnstaked(RECEIVER, 10 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.RemoveCollateral(CREDIT_ACCOUNT, CREDIT_ACCOUNT, RECEIVER, 10 ether);
        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        vm.clearMockedCalls();

        assertEq(assets, 10 ether);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, 0);
        assertEq(collateralToken.balanceOf(RECEIVER), 10 ether);
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(rewardPool.lastWithdrawAmount(), 10 ether);
        assertFalse(rewardPool.lastWithdrawClaim());
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
        assertEq(market.stakedCollateralAssets(), 80 ether);
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
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidOraclePrice.selector);
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
        deal(address(borrowToken), USER, burnAssets);
        vm.prank(USER);
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
