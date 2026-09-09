// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    IAltoConvexCreditLineMarketErrors,
    IAltoConvexCreditLineMarketEvents
} from "@alto/lending/interfaces/IAltoConvexCreditLineMarket.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";

import {ConvexCreditLineCommon} from "./ConvexCreditLineCommon.t.sol";

contract AltoConvexCreditLineMarketEmergencyExitTest is ConvexCreditLineCommon {
    function test_RevertWhenCallerIsNotOwner() external {
        _pause(PAUSE_TYPE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        market.emergencyExitConvex();
    }

    function test_MustBePausedEvenWhenFrozenOrAlreadyInactive() external {
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineMustBePaused.selector);
        market.emergencyExitConvex();

        _pause(FROZEN_TYPE);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineMustBePaused.selector);
        market.emergencyExitConvex();

        _unpause(FROZEN_TYPE);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineMustBePaused.selector);
        market.emergencyExitConvex();

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineStrategyInactive.selector);
        market.emergencyExitConvex();
    }

    function test_ZeroStakeSkipsWithdrawalPreservesIdleAndLeavesAllowanceZero() external {
        deal(address(collateralToken), address(market), 3 ether);
        _pause(PAUSE_TYPE);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.ConvexEmergencyExit(0);
        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 0);
        assertEq(rewardPool.withdrawCalls(), 0);
        assertEq(collateralToken.balanceOf(address(market)), 3 ether);
        assertFalse(market.convexActive());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_StakeAndWithdrawalFailuresKeepStrategyActive() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        AccountingState memory beforeState = _state();

        vm.mockCallRevert(
            address(rewardPool), abi.encodeWithSignature("balanceOf(address)", address(market)), "BALANCE_REVERTED"
        );
        vm.prank(OWNER);
        vm.expectRevert(bytes("BALANCE_REVERTED"));
        market.emergencyExitConvex();
        vm.clearMockedCalls();
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(true, true, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(bytes("WITHDRAW_REVERTED"));
        market.emergencyExitConvex();
        _assertUnchanged(beforeState);

        rewardPool.setWithdrawBehavior(false, false, type(uint256).max, type(uint256).max);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineExternalCallFailed.selector);
        market.emergencyExitConvex();
        _assertUnchanged(beforeState);
        assertTrue(market.convexActive());
    }

    function test_DoesNotValidateRecoveredLpDelta() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        rewardPool.setWithdrawBehavior(false, true, 9 ether, 10 ether);

        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 10 ether);
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(collateralToken.balanceOf(address(market)), 9 ether);
        assertFalse(market.convexActive());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        (,, uint128 collateralAssets) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAssets, 10 ether);
    }

    function test_DoesNotQueryCollateralBalanceAfterWithdrawal() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        collateralToken.setBalanceFailure(false, true);

        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        collateralToken.setBalanceFailure(false, false);
        assertEq(assets, 10 ether);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether);
        assertFalse(market.convexActive());
    }

    function test_ApprovalFailureCannotBlockEmergencyExit() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        collateralToken.setApproveFailure(true);

        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 10 ether);
        assertFalse(market.convexActive());
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_SuccessRecoversAllStakePreservesIdleAndAccounting() external {
        _openPosition(100 ether, 10 ether);
        deal(address(collateralToken), address(market), 3 ether);
        AccountingState memory beforePause = _state();
        _pause(PAUSE_TYPE);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.ConvexEmergencyExit(100 ether);
        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 100 ether);
        assertEq(rewardPool.lastWithdrawAmount(), 100 ether);
        assertFalse(rewardPool.lastWithdrawClaim());
        assertEq(market.stakedCollateralAssets(), 0);
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(collateralToken.balanceOf(address(market)), 103 ether);
        assertFalse(market.convexActive());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        AccountingState memory afterState = _state();
        assertEq(afterState.totalSupply.assets, beforePause.totalSupply.assets);
        assertEq(afterState.totalBorrowed.assets, beforePause.totalBorrowed.assets);
        assertEq(afterState.creditPosition.collateralAssets, beforePause.creditPosition.collateralAssets);
        assertEq(afterState.creditPosition.borrowShares, beforePause.creditPosition.borrowShares);
    }

    function test_PostExitLifecycleUsesIdleCollateralButRejectsNewDepositsAndSecondExit() external {
        _addCollateral(10 ether);
        _exitConvex();
        _unpause(PAUSE_TYPE);
        uint256 withdrawalsBefore = rewardPool.withdrawCalls();

        vm.prank(CREDIT_ACCOUNT);
        uint256 assets = market.removeCollateral(10 ether, CREDIT_ACCOUNT, RECEIVER, "");
        assertEq(assets, 10 ether);
        assertEq(collateralToken.balanceOf(RECEIVER), 10 ether);
        assertEq(collateralToken.balanceOf(address(market)), 0);
        (,, uint128 collateralAfter) = market.position(CREDIT_ACCOUNT);
        assertEq(collateralAfter, 0);
        assertEq(rewardPool.withdrawCalls(), withdrawalsBefore);

        deal(address(collateralToken), USER, 1 ether);
        vm.prank(USER);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(USER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoCreditMarketInvalidInput.selector);
        market.addCollateral(1 ether, CREDIT_ACCOUNT);

        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        vm.expectRevert(IAltoConvexCreditLineMarketErrors.AltoConvexCreditLineStrategyInactive.selector);
        market.emergencyExitConvex();
    }

    function test_UsesReportedStakeEvenWhenItDiffersFromRecordedCollateral() external {
        _addCollateral(10 ether);
        rewardPool.setStake(address(market), 6 ether);
        deal(address(collateralToken), address(rewardPool), 6 ether);
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();
        assertEq(assets, 6 ether);
        assertEq(collateralToken.balanceOf(address(market)), 6 ether);
        (,, uint128 recordedCollateral) = market.position(CREDIT_ACCOUNT);
        assertEq(recordedCollateral, 10 ether);

        // A fresh deployment also recovers stake exceeding its recorded collateral.
        setUp();
        rewardPool.setStake(address(market), 15 ether);
        deal(address(collateralToken), address(rewardPool), 15 ether);
        _pause(PAUSE_TYPE);
        vm.prank(OWNER);
        assets = market.emergencyExitConvex();
        assertEq(assets, 15 ether);
        assertEq(collateralToken.balanceOf(address(market)), 15 ether);
    }

    function test_RejectsRewardPoolReentrancyAtomically() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        rewardPool.setCallback(address(market), abi.encodeCall(market.emergencyExitConvex, ()), true, false);
        AccountingState memory beforeState = _state();

        vm.prank(OWNER);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        market.emergencyExitConvex();

        _assertUnchanged(beforeState);
        assertTrue(market.convexActive());
    }
}
