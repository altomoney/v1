// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {IMarketEvents} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {AdaptiveCurveIrm} from "@alto/lending/irm/AdaptiveCurveIrm.sol";
import {PegResponsiveExponentialIrm} from "@alto/lending/irm/PegResponsiveExponentialIrm.sol";
import {MockDusdPegOracle} from "@alto-test/lending/btt/mocks/MockDusdPegOracle.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketAccrueInterestTest is ConvexCreditLineCommon {
    function test_AdaptiveIrmAccruesAndRespondsToCreditUtilization() external {
        AdaptiveCurveIrm candidate = _newAdaptiveCurveIrm();
        _assertVariableIrmAccrualAndPause(candidate);

        (uint128 debt,) = market.totalBorrowed();
        (, uint256 lowUtilizationRate) = candidate.updateInterestRateView(CREDIT_LIMIT, debt);
        uint256 newCreditLimit = uint256(debt) * 2;
        vm.prank(OWNER);
        market.setCreditLimit(newCreditLimit);
        (, uint256 higherUtilizationRate) = candidate.updateInterestRateView(newCreditLimit, debt);
        assertGt(higherUtilizationRate, lowUtilizationRate);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(higherUtilizationRate, 0, debt, uint128(newCreditLimit));
        market.accrueInterest();
    }

    function test_PegResponsiveIrmAccruesAndRespondsToPegPrice() external {
        PegResponsiveExponentialIrm candidate = _newPegResponsiveIrm();
        _assertVariableIrmAccrualAndPause(candidate);

        MockDusdPegOracle(candidate.pegOracle()).setPrice(0.99 ether, uint48(block.timestamp), true);
        market.accrueInterest();
        (uint256 stressedRate,,,) = candidate.irState();
        assertGt(stressedRate, BORROW_RATE);

        vm.warp(block.timestamp + 1 days);
        (uint128 debt,) = market.totalBorrowed();
        (uint256 interest, uint256 rate) = candidate.updateInterestRateView(CREDIT_LIMIT, debt);
        assertEq(rate, stressedRate);
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(rate, interest, uint128(uint256(debt) + interest), uint128(CREDIT_LIMIT));
        market.accrueInterest();
    }

    function test_RevertWhenPaused() external {
        _pause(PAUSE_TYPE);
        _assertPausedRevert(PAUSE_TYPE);
        market.accrueInterest();
    }

    function test_PassesCreditLimitAndCurrentDebtOnlyToIrmWithoutUnrelatedInteractions() external {
        _openPosition(1_000 ether, 100 ether);
        uint256 depositsBefore = booster.depositCalls();
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();
        uint256 rewardClaimsBefore = rewardPool.getRewardCalls();
        AccountingState memory beforeState = _state();
        _mockAccrual(0, 17);

        vm.mockCallRevert(address(oracle), abi.encodeCall(ILendingOracle.getPrice, ()), "ORACLE_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(
            address(rewardPool),
            abi.encodeWithSignature("balanceOf(address)", address(market)),
            "REWARD_POOL_BALANCE_MUST_NOT_BE_CALLED"
        );
        booster.setDepositBehavior(true, true, type(uint256).max, type(uint256).max);
        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        rewardPool.setRewardBehavior(true, true);
        _setTokenCallsToRevert(true);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 100 ether)));
        market.accrueInterest();
        vm.clearMockedCalls();
        _setTokenCallsToRevert(false);

        assertEq(booster.depositCalls(), depositsBefore);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);
        assertEq(rewardPool.getRewardCalls(), rewardClaimsBefore);
        _assertUnchanged(beforeState);
    }

    function test_ZeroInterestCallsIrmEmitsAndPreservesAllAccounting() external {
        _openPosition(1 ether, 1);
        AccountingState memory beforeState = _state();
        (uint256 borrowRate, uint48 lastUpdateBefore) = irm.irState();
        vm.warp(block.timestamp + 1);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 1)));
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(borrowRate, 0, 1, uint128(CREDIT_LIMIT));
        market.accrueInterest();

        (, uint48 lastUpdateAfter) = irm.irState();
        assertGt(lastUpdateAfter, lastUpdateBefore);
        assertEq(lastUpdateAfter, block.timestamp);
        _assertUnchanged(beforeState);
    }

    function test_NonzeroInterestUpdatesOnlyDebtAssetsAndClaimableFees() external {
        _openPosition(1_000 ether, 100 ether);
        AccountingState memory beforeState = _state();
        _mockAccrual(7 ether, 31);

        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(31, 7 ether, 107 ether, uint128(CREDIT_LIMIT));
        market.accrueInterest();

        AccountingState memory afterState = _state();
        assertEq(afterState.totalBorrowed.assets, beforeState.totalBorrowed.assets + 7 ether);
        assertEq(afterState.claimableFees, beforeState.claimableFees + 7 ether);
        assertEq(afterState.totalBorrowed.shares, beforeState.totalBorrowed.shares);
        assertEq(afterState.totalSupply.assets, beforeState.totalSupply.assets);
        assertEq(afterState.totalSupply.shares, beforeState.totalSupply.shares);
        assertEq(afterState.creditPosition.borrowShares, beforeState.creditPosition.borrowShares);
        assertEq(afterState.creditPosition.collateralAssets, beforeState.creditPosition.collateralAssets);
    }

    function test_BadDebtDoesNotAccrueAndIsExcludedFromIrmDebtInput() external {
        _openPosition(1_000 ether, 100 ether);
        oracle.setPrice(100 ether);
        vm.prank(OWNER);
        market.governanceLiquidate(CREDIT_ACCOUNT, false);

        oracle.setPrice(LENDING_ORACLE_PRICE_PRECISION);
        _addCollateral(1_000 ether);
        _mockAccrual(0, 0);
        _borrow(50 ether);
        _mockAccrual(5 ether, 41);

        vm.expectCall(address(irm), abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 50 ether)));
        market.accrueInterest();

        (uint128 debtAssets,) = market.totalBorrowed();
        assertEq(debtAssets, 55 ether);
        assertEq(market.claimableFeesAssets(), 5 ether);
        assertEq(market.badDebtAssets(), 100 ether);
    }

    function test_IrmRevertOrMalformedReturnRollsBack() external {
        AccountingState memory beforeState = _state();
        _mockIrmUpdateRevert();
        vm.expectRevert(bytes("UPDATE_REVERTED"));
        market.accrueInterest();
        _assertUnchanged(beforeState);

        vm.clearMockedCalls();
        bytes memory updateCall = abi.encodeCall(IIrm.updateInterestRate, (CREDIT_LIMIT, 0));
        vm.mockCall(address(irm), updateCall, hex"01");
        vm.expectRevert();
        market.accrueInterest();
        vm.clearMockedCalls();
        _assertUnchanged(beforeState);
    }

    function _assertVariableIrmAccrualAndPause(IIrm candidate) private {
        _openPosition(1_000 ether, 100 ether);
        vm.warp(block.timestamp + 1 days);
        (uint256 oldInterest,) = irm.updateInterestRateView(CREDIT_LIMIT, 100 ether);
        assertGt(oldInterest, 0);

        vm.prank(OWNER);
        market.setIrm(address(candidate), false);
        AccountingState memory beforeState = _state();
        assertEq(beforeState.totalBorrowed.assets, 100 ether + oldInterest);
        assertEq(beforeState.claimableFees, oldInterest);

        vm.warp(block.timestamp + 1 days);
        (uint256 interest, uint256 rate) =
            candidate.updateInterestRateView(CREDIT_LIMIT, beforeState.totalBorrowed.assets);
        assertGt(interest, 0);
        uint128 expectedDebt = uint128(uint256(beforeState.totalBorrowed.assets) + interest);
        vm.expectEmit(address(market));
        emit IMarketEvents.AccrueInterest(rate, interest, expectedDebt, uint128(CREDIT_LIMIT));
        market.accrueInterest();

        AccountingState memory expectedState = beforeState;
        expectedState.totalBorrowed.assets = expectedDebt;
        expectedState.claimableFees += uint128(interest);
        _assertStateEq(_state(), expectedState);

        _pause(PAUSE_TYPE);
        vm.warp(block.timestamp + 7 days);
        _unpause(PAUSE_TYPE);
        market.accrueInterest();
        _assertStateEq(_state(), expectedState);
    }

    function _setTokenCallsToRevert(bool shouldRevert) private {
        _setTokenCallsToRevert(address(borrowToken), shouldRevert);
        _setTokenCallsToRevert(address(collateralToken), shouldRevert);
        _setTokenCallsToRevert(address(depositToken), shouldRevert);
        _setTokenCallsToRevert(address(primaryRewardToken), shouldRevert);
        _setTokenCallsToRevert(address(extraRewardToken), shouldRevert);
    }

    function _setTokenCallsToRevert(address token, bool shouldRevert) private {
        if (!shouldRevert) return;
        vm.mockCallRevert(token, IERC20.balanceOf.selector, "TOKEN_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(token, IERC20.transfer.selector, "TOKEN_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(token, IERC20.transferFrom.selector, "TOKEN_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(token, IERC20.approve.selector, "TOKEN_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(token, IMintableERC20.mint.selector, "TOKEN_MUST_NOT_BE_CALLED");
        vm.mockCallRevert(token, IMintableERC20.burn.selector, "TOKEN_MUST_NOT_BE_CALLED");
    }
}
