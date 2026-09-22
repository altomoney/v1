// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

    function test_ApprovalFailureCannotBlockEmergencyExit() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        collateralToken.setApproveFailure(true);

        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 10 ether);
        assertFalse(market.convexActive());
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether);
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
    }

    function test_WithdrawalCallbackObservesInactiveStrategy() external {
        _addCollateral(10 ether);
        _pause(PAUSE_TYPE);
        rewardPool.setCallback(address(this), abi.encodeCall(this.assertInactiveDuringWithdrawal, ()), true, false);

        vm.expectCall(address(this), abi.encodeCall(this.assertInactiveDuringWithdrawal, ()));
        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 10 ether);
        assertFalse(market.convexActive());
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(collateralToken.balanceOf(address(market)), 10 ether);
    }

    function assertInactiveDuringWithdrawal() external view {
        assertEq(msg.sender, address(rewardPool));
        assertFalse(market.convexActive());
    }

    function test_SuccessRecoversAllStakePreservesIdleAndAccounting() external {
        _openPosition(100 ether, 10 ether);
        deal(address(collateralToken), address(market), 3 ether);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(primaryRewardToken);
        uint256[] memory rewardAmounts = new uint256[](1);
        rewardAmounts[0] = 5 ether;
        rewardPool.setRewards(rewardTokens, rewardAmounts);
        AccountingState memory beforePause = _state();
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);
        uint256 creditCollateralBefore = collateralToken.balanceOf(CREDIT_ACCOUNT);
        uint256 rewardClaimsBefore = rewardPool.getRewardCalls();
        uint256 recipientRewardBefore = primaryRewardToken.balanceOf(REWARD_RECIPIENT);
        _pause(PAUSE_TYPE);

        vm.expectEmit(address(market));
        emit IAltoConvexCreditLineMarketEvents.ConvexEmergencyExit(100 ether);
        vm.prank(OWNER);
        uint256 assets = market.emergencyExitConvex();

        assertEq(assets, 100 ether);
        assertEq(rewardPool.lastWithdrawAmount(), 100 ether);
        assertFalse(rewardPool.lastWithdrawClaim());
        assertEq(rewardPool.balanceOf(address(market)), 0);
        assertEq(collateralToken.balanceOf(address(market)), 103 ether);
        assertFalse(market.convexActive());
        assertEq(collateralToken.allowance(address(market), address(booster)), 0);
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore);
        assertEq(collateralToken.balanceOf(CREDIT_ACCOUNT), creditCollateralBefore);
        assertEq(rewardPool.getRewardCalls(), rewardClaimsBefore);
        assertEq(primaryRewardToken.balanceOf(REWARD_RECIPIENT), recipientRewardBefore);
        AccountingState memory afterState = _state();
        afterState.idleCollateral = beforePause.idleCollateral;
        afterState.stakedCollateral = beforePause.stakedCollateral;
        _assertStateEq(afterState, beforePause);
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

        deal(address(collateralToken), CREDIT_ACCOUNT, 1 ether);
        vm.prank(CREDIT_ACCOUNT);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(CREDIT_ACCOUNT);
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
}
