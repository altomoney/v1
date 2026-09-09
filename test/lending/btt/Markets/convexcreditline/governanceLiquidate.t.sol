// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAltoCreditMarketErrors} from "@alto/lending/interfaces/IAltoCreditMarket.sol";
import {
    IAltoConvexCreditLineErrors,
    IAltoConvexCreditLineEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLine.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketGovernanceLiquidateTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.governanceLiquidate(CREDIT_ACCOUNT);
    }

    function test_BorrowerCheckPrecedesAccrual() external {
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.governanceLiquidate(USER);
    }

    function test_AvailableWhenActiveFrozenOrPaused() external {
        _openForeclosablePosition();
        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT);

        setUp();
        _openForeclosablePosition();
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT);
    }

    function test_StrictForeclosureThresholdAndPostAccrualEligibility() external {
        _addCollateral(1_000 ether);
        _borrow(90 ether);
        oracle.setPrice(1e35 + 1);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);

        oracle.setPrice(1e35);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);

        _mockAccrual(1 ether, 1);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
    }

    function test_NoDebtZeroOracleAndDependencyFailuresRevertAtomically() external {
        _addCollateral(10 ether);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);

        _borrow(1 ether);
        AccountingState memory beforeState = _state();
        oracle.setPrice(0);
        vm.prank(OWNER);
        vm.expectRevert(IAltoCreditMarketErrors.AltoCreditMarketInvalidOraclePrice.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        oracle.setPrice(100 ether);
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_ActiveConvexWithdrawalFailuresRestoreForeclosureAccounting() external {
        _openForeclosablePosition();
        AccountingState memory beforeState = _state();
        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(bytes("WITHDRAW_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, true, 999 ether, 1_000 ether);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);
    }

    function test_InactiveStrategyRequiresIdleCoverageAndPreservesSurplus() external {
        _openForeclosablePosition();
        _exitConvex();
        deal(address(collateralToken), address(market), 999 ether);
        AccountingState memory beforeState = _state();
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineErrors.AltoConvexCreditLineUnexpectedAssetDelta.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        _assertUnchanged(beforeState);

        deal(address(collateralToken), address(market), 1_003 ether);
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT);
        assertEq(collateralToken.balanceOf(OWNER), 1_000 ether);
        assertEq(market.idleCollateralAssets(), 3 ether);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
    }

    function test_CollateralTransferFailureRollsBackEverything() external {
        _openForeclosablePosition();
        _exitConvex();
        collateralToken.setTransferBehavior(true, false, 10_000, 0);
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(bytes("TRANSFER_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT);

        _assertUnchanged(beforeState);
    }

    function test_ZeroCollateralStillClearsForeclosableDebtWithoutCustodyCall() external {
        _openPosition(10 ether, 1 ether);
        bytes32 positionBase = keccak256(abi.encode(CREDIT_ACCOUNT, uint256(8)));
        vm.store(address(market), bytes32(uint256(positionBase) + 1), bytes32(0));
        uint256 callsBefore = rewardPool.withdrawCalls();

        vm.prank(OWNER);
        (uint256 collateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT);

        assertEq(collateral, 0);
        assertEq(badDebt, 1 ether);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
    }

    function test_SuccessClearsDebtAndCollateralButPreservesCapacityFeesAndMintedDebtTokens() external {
        _setOpeningFee(0.1 ether);
        _addCollateral(1_000 ether);
        _borrow(100 ether);
        oracle.setPrice(100 ether);
        _mockAccrual(5 ether, 37);
        uint256 tokenSupplyBefore = borrowToken.totalSupply();
        uint256 creditLimitBefore = market.creditLimit();
        uint256 claimableBefore = market.claimableFeesAssets();
        (, uint128 sharesBefore,) = market.position(CREDIT_ACCOUNT);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(37, 5 ether, 115 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineEvents.CollateralUnstaked(OWNER, 1_000 ether);
        vm.expectEmit(address(market));
        emit IMarketEvents.GovernanceLiquidation(CREDIT_ACCOUNT, OWNER, 1_000 ether, 115 ether, sharesBefore);
        vm.prank(OWNER);
        (uint256 collateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT);

        assertEq(collateral, 1_000 ether);
        assertEq(badDebt, 115 ether);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
        (, uint128 positionShares, uint128 positionCollateral) = market.position(CREDIT_ACCOUNT);
        assertEq(positionShares, 0);
        assertEq(positionCollateral, 0);
        assertEq(market.creditLimit(), creditLimitBefore);
        assertEq(market.claimableFeesAssets(), claimableBefore + 5 ether);
        assertEq(borrowToken.totalSupply(), tokenSupplyBefore);
        assertTrue(market.convexActive());
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);

        // Cleared bad debt immediately frees the same synthetic capacity for a new secured draw.
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(100 ether);
        (debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 110 ether);
    }

    function _openForeclosablePosition() private {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
    }
}
