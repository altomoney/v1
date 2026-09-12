// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {IMarketErrors, IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketGovernanceLiquidateTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
    }

    function test_BorrowerCheckPrecedesAccrual() external {
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketUnauthorizedAccount.selector);
        market.governanceLiquidate(USER, false);
    }

    function test_AvailableWhenActiveFrozenOrPaused() external {
        _openForeclosablePosition();
        _pause(FROZEN_TYPE);
        _mockAccrual(5 ether, 1);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 105 ether);

        setUp();
        _openForeclosablePosition();
        _pause(PAUSE_TYPE);
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 100 ether);
    }

    function test_StrictForeclosureThresholdAndConditionalAccrualEligibility() external {
        _addCollateral(1_000 ether);
        _borrow(90 ether);
        oracle.setPrice(1e35 + 1);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        oracle.setPrice(1e35);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        _mockAccrual(1 ether, 1);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, true);

        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
        assertEq(market.badDebtAssets(), 91 ether);
    }

    function test_SkipAccrualUsesRecordedDebtWithoutCallingIrm() external {
        _openForeclosablePosition();
        _mockIrmUpdateRevert();

        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, true);

        assertEq(market.badDebtAssets(), 100 ether);
    }

    function test_NoDebtZeroOracleAndDependencyFailuresRevertAtomically() external {
        _addCollateral(10 ether);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketPositionNotForeclosable.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        _borrow(1 ether);
        AccountingState memory beforeState = _state();
        oracle.setPrice(0);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidOraclePrice.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _assertUnchanged(beforeState);

        oracle.setPrice(100 ether);
        _mockIrmUpdateRevert();
        vm.prank(OWNER);
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _assertUnchanged(beforeState);
    }

    function test_ActiveConvexWithdrawalFailuresRestoreForeclosureAccounting() external {
        _openForeclosablePosition();
        AccountingState memory beforeState = _state();
        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(bytes("WITHDRAW_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, true, 999 ether, 1_000 ether);
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(market), 999 ether, 1_000 ether
            )
        );
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        _assertUnchanged(beforeState);
    }

    function test_InactiveStrategyForeclosesUsingRecoveredCollateralWithoutCallingConvexAndPreservesSurplus() external {
        _openForeclosablePosition();
        _exitConvex();
        deal(address(collateralToken), address(market), 1_003 ether);
        uint256 ownerBalanceBefore = collateralToken.balanceOf(OWNER);
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();

        vm.prank(OWNER);
        (uint256 collateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(collateral, 1_000 ether);
        assertEq(badDebt, 100 ether);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
        (, uint128 positionShares, uint128 positionCollateral) = market.position(CREDIT_ACCOUNT);
        assertEq(positionShares, 0);
        assertEq(positionCollateral, 0);
        assertEq(market.badDebtAssets(), 100 ether);
        assertEq(collateralToken.balanceOf(OWNER), ownerBalanceBefore + 1_000 ether);
        assertEq(collateralToken.balanceOf(address(market)), 3 ether);
        assertFalse(market.convexActive());
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
    }

    function test_InactiveStrategyWithInsufficientIdleCollateralRevertsForeclosureAtomically() external {
        _openForeclosablePosition();
        _exitConvex();
        deal(address(collateralToken), address(market), 999 ether);
        AccountingState memory beforeState = _state();
        uint256 ownerBalanceBefore = collateralToken.balanceOf(OWNER);
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(market), 999 ether, 1_000 ether
            )
        );
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        _assertUnchanged(beforeState);
        assertEq(collateralToken.balanceOf(OWNER), ownerBalanceBefore);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
    }

    function test_CollateralTransferFailureRollsBackEverything() external {
        _openForeclosablePosition();
        vm.mockCallRevert(
            address(collateralToken),
            abi.encodeCall(collateralToken.transfer, (OWNER, 1_000 ether)),
            bytes("TRANSFER_REVERTED")
        );
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(bytes("TRANSFER_REVERTED"));
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        vm.clearMockedCalls();

        _assertUnchanged(beforeState);
    }

    function test_ZeroCollateralStillClearsForeclosableDebtWithoutCustodyCall() external {
        _openPosition(10 ether, 1 ether);
        bytes32 positionBase = keccak256(abi.encode(CREDIT_ACCOUNT, uint256(8)));
        vm.store(address(market), bytes32(uint256(positionBase) + 1), bytes32(0));
        uint256 callsBefore = rewardPool.withdrawCalls();

        vm.prank(OWNER);
        (uint256 collateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(collateral, 0);
        assertEq(badDebt, 1 ether);
        assertEq(market.badDebtAssets(), 1 ether);
        assertEq(rewardPool.withdrawCalls(), callsBefore);
    }

    function test_SuccessClearsDebtAndCollateralAndTracksBadDebtFeesAndMintedDebtTokens() external {
        _setOpeningFee(0.1 ether);
        _addCollateral(1_000 ether);
        _borrow(100 ether);
        oracle.setPrice(100 ether);
        _mockAccrual(5 ether, 37);
        uint256 tokenSupplyBefore = borrowToken.totalSupply();
        (uint128 supplyAssetsBefore, uint128 supplySharesBefore) = market.totalSupply();
        uint256 creditLimitBefore = supplyAssetsBefore;
        uint256 claimableBefore = market.claimableFeesAssets();
        (, uint128 sharesBefore,) = market.position(CREDIT_ACCOUNT);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(37, 5 ether, 115 ether, uint128(CREDIT_LIMIT));
        vm.expectEmit(address(market));
        emit IMarketEvents.GovernanceLiquidation(CREDIT_ACCOUNT, OWNER, 1_000 ether, 115 ether, sharesBefore);
        vm.prank(OWNER);
        (uint256 collateral, uint256 badDebt) = market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(collateral, 1_000 ether);
        assertEq(badDebt, 115 ether);
        (uint128 debtAssets, uint128 debtShares) = market.totalBorrowed();
        assertEq(debtAssets, 0);
        assertEq(debtShares, 0);
        (, uint128 positionShares, uint128 positionCollateral) = market.position(CREDIT_ACCOUNT);
        assertEq(positionShares, 0);
        assertEq(positionCollateral, 0);
        (uint128 supplyAssetsAfter, uint128 supplySharesAfter) = market.totalSupply();
        assertEq(supplyAssetsAfter, creditLimitBefore);
        assertEq(supplyAssetsAfter, supplyAssetsBefore);
        assertEq(supplySharesAfter, supplySharesBefore);
        assertEq(market.claimableFeesAssets(), claimableBefore + 5 ether);
        assertEq(market.badDebtAssets(), 115 ether);
        assertEq(borrowToken.totalSupply(), tokenSupplyBefore);
        assertTrue(market.convexActive());
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);

        // New secured draws use only the credit limit remaining after bad debt.
        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(100 ether);
        (debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 110 ether);
        assertEq(market.badDebtAssets(), 115 ether);
    }

    function test_PendingRewardsRemainClaimableAfterForeclosure() external {
        _openForeclosablePosition();
        address[] memory tokens = new address[](2);
        tokens[0] = address(primaryRewardToken);
        tokens[1] = address(extraRewardToken);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3 ether;
        amounts[1] = 5 ether;
        rewardPool.setRewards(tokens, amounts);
        uint256 claimsBefore = rewardPool.getRewardCalls();

        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        assertEq(rewardPool.getRewardCalls(), claimsBefore);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 0);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 0);

        vm.prank(USER);
        uint256[] memory claimed = market.claimRewards();

        assertEq(claimed[0], 3 ether);
        assertEq(claimed[1], 5 ether);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), 3 ether);
        assertEq(extraRewardToken.balanceOf(REWARD_RECIPIENT), 5 ether);
        assertEq(market.badDebtAssets(), 100 ether);
    }

    function test_RepeatedForeclosuresAccumulateBadDebtAndEventuallyExhaustCapacity() external {
        vm.prank(OWNER);
        market.setCreditLimit(200 ether);

        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 100 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(100 ether);
        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 100 ether);

        AccountingState memory beforeState = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);

        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);
        assertEq(market.badDebtAssets(), 200 ether);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        beforeState = _state();
        vm.prank(CREDIT_ACCOUNT);
        vm.expectRevert(IMarketErrors.AltoBaseMarketInsufficientMarketLiquidity.selector);
        market.borrow(1, 0, CREDIT_ACCOUNT, RECEIVER, "");
        _assertUnchanged(beforeState);
    }

    function _openForeclosablePosition() private {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
    }
}
