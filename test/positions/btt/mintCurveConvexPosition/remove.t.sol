// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionCommon} from "./MintCurveConvexPositionCommon.t.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    IMintCurveConvexPositionEvents,
    IMintCurveConvexPositionErrors,
    MintCurveConvexRemoveMode,
    MintCurveConvexRemoveParams
} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {SwapPositionLib} from "@alto/positions/libraries/SwapPositionLib.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MintCurveConvexPosition_Remove_Test is MintCurveConvexPositionCommon {
    uint256 internal stakedLp;
    uint256 internal constant WITHDRAW_LP = 500e18;

    function setUp() public override {
        super.setUp();
        stakedLp = _addWithBorrow(DEFAULT_COLLATERAL, DEFAULT_BORROW);
        assertGt(stakedLp, 0);
    }

    function test_RevertWhen_CallerIsNotOwnerOrAuthorizedSpender() public {
        vm.prank(NON_AUTHORIZED);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionUnauthorized.selector);
        position.remove(_encodeRemove(_defaultRemoveParams()));
    }

    function test_RevertWhen_RemoveModeIsInvalid() public {
        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();

        vm.prank(OWNER);
        vm.expectRevert();
        position.remove(_encodeRemoveWithMode(2, params));
    }

    function test_Remove_Normal_WhenClaimRewardsIsFalse() public {
        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.claimRewards = false;

        uint256 withdrawCallsBefore = convexRewardPool.withdrawCallCount();

        vm.recordLogs();
        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(convexRewardPool.withdrawCallCount(), withdrawCallsBefore + 1);
        assertEq(convexRewardPool.lastWithdrawAmount(), WITHDRAW_LP);
        assertFalse(convexRewardPool.lastWithdrawClaimRewards());
        assertEq(curvePool.lastLpRemoved(), WITHDRAW_LP);
        assertFalse(_logsContainClaimRewards());
    }

    function test_Remove_Normal_WhenClaimRewardsIsTrue() public {
        _fundRewards(25e18, 10e18);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.claimRewards = true;

        uint256 ownerCrvBefore = crv.balanceOf(OWNER);
        uint256 ownerCvxBefore = cvx.balanceOf(OWNER);

        vm.recordLogs();
        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertTrue(convexRewardPool.lastWithdrawClaimRewards());
        assertEq(crv.balanceOf(OWNER), ownerCrvBefore + 25e18);
        assertEq(cvx.balanceOf(OWNER), ownerCvxBefore + 10e18);
        assertEq(curvePool.lastLpRemoved(), WITHDRAW_LP);
        assertTrue(_logsContainClaimRewards());
    }

    function test_Remove_Normal_WhenConvexLpAmountIsFullStakedLp() public {
        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = stakedLp;

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(convexRewardPool.lastWithdrawAmount(), stakedLp);
    }

    function test_Remove_Normal_WhenPositionHasZeroStakedLpAndConvexLpAmountIsZero() public {
        MintCurveConvexPosition fresh = _createPosition(OWNER);
        _mintCollateralFor(address(fresh), DEFAULT_COLLATERAL);
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();
        vm.prank(OWNER);
        fresh.add(_encodeAdd(_addParams(DEFAULT_COLLATERAL, 0, 0, minFrxOut, minLpOut)));

        uint256 fraxAmount = 100e18;
        frxUsd.mint(address(fresh), fraxAmount);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.frxUsdAmountToSwap = fraxAmount;
        params.swapData = _swapDataFrxToDusd(fraxAmount);
        params.repayShares = 0;
        params.collateralAmountToWithdraw = 0;

        uint256 withdrawCallsBefore = convexRewardPool.withdrawCallCount();
        uint256 removeLiquidityCallsBefore = curvePool.removeLiquidityCallCount();
        uint256 swapCallsBefore = swapTarget.swapCallCount();
        Position memory marketPositionBefore = _marketPosition(address(fresh));

        vm.recordLogs();
        vm.prank(OWNER);
        fresh.remove(_encodeRemove(params));

        assertEq(convexRewardPool.withdrawCallCount(), withdrawCallsBefore);
        assertEq(curvePool.removeLiquidityCallCount(), removeLiquidityCallsBefore);
        assertEq(swapTarget.swapCallCount(), swapCallsBefore + 1);
        assertEq(swapTarget.lastAmountIn(), fraxAmount);
        assertEq(swapTarget.lastSellToken(), address(frxUsd));
        assertEq(swapTarget.lastBuyToken(), address(borrowToken));
        assertEq(IERC20(address(frxUsd)).allowance(address(fresh), address(swapTarget)), 0);
        assertEq(_marketPosition(address(fresh)).collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition(address(fresh)).borrowShares, marketPositionBefore.borrowShares);
        assertGt(borrowToken.balanceOf(OWNER), 0);
        _assertSwapLogged(address(frxUsd), address(borrowToken), fraxAmount, address(swapTarget), 0, vm.getRecordedLogs());
    }

    function test_Remove_Normal_SkipsFrxUsdToDusdSwapWhenFraxAmountIsZero() public {
        uint256 swapCallsBefore = swapTarget.swapCallCount();
        Position memory marketPositionBefore = _marketPosition();

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(swapTarget.swapCallCount(), swapCallsBefore);
        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition().borrowShares, marketPositionBefore.borrowShares);
    }

    function test_RevertWhen_NormalFraxSwapAndSwapTargetIsNotApproved() public {
        frxUsd.mint(address(position), 100e18);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.frxUsdAmountToSwap = 100e18;
        params.swapTarget = UNAPPROVED_SWAP_TARGET;

        vm.prank(OWNER);
        vm.expectRevert(IMintCurveConvexPositionErrors.MintCurveConvexPositionInvalidInput.selector);
        position.remove(_encodeRemove(params));
    }

    function test_RevertWhen_NormalFraxSwapAndSwapTargetCallFails() public {
        frxUsd.mint(address(position), 100e18);
        swapTarget.setSwapOutcome(true, 0);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.frxUsdAmountToSwap = 100e18;

        vm.prank(OWNER);
        vm.expectRevert(SwapPositionLib.SwapPositionSwapFailed.selector);
        position.remove(_encodeRemove(params));
    }

    function test_RevertWhen_NormalFraxSwapAndDusdReceivedIsLessThanMinDusdFromSwap() public {
        frxUsd.mint(address(position), 100e18);
        swapTarget.setSwapOutcome(false, 1);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.frxUsdAmountToSwap = 100e18;
        params.minDusdOutFromFrxUsdSwap = 100e18;

        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(SwapPositionLib.SwapPositionMinAmountOutNotMet.selector, params.minDusdOutFromFrxUsdSwap, 1)
        );
        position.remove(_encodeRemove(params));
    }

    function test_Remove_Normal_SwapsFrxUsdToDusdWhenSwapSucceeds() public {
        uint256 fraxAmount = 100e18;
        frxUsd.mint(address(position), fraxAmount);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.frxUsdAmountToSwap = fraxAmount;
        Position memory marketPositionBefore = _marketPosition();

        vm.recordLogs();
        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(swapTarget.lastAmountIn(), fraxAmount);
        assertEq(swapTarget.lastSellToken(), address(frxUsd));
        assertEq(swapTarget.lastBuyToken(), address(borrowToken));
        assertEq(IERC20(address(frxUsd)).allowance(address(position), address(swapTarget)), 0);
        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition().borrowShares, marketPositionBefore.borrowShares);
        _assertSwapLogged(address(frxUsd), address(borrowToken), fraxAmount, address(swapTarget), 0, vm.getRecordedLogs());
    }

    function test_Remove_Normal_SkipsMintMarketRepaymentWhenRepaySharesIsZero() public {
        Position memory marketPositionBefore = _marketPosition();

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.repayShares = 0;

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition().borrowShares, marketPositionBefore.borrowShares);
    }

    function test_RevertWhen_NormalRepayAndPositionLacksDusd() public {
        uint256 repayShares = _marketPosition().borrowShares;
        assertGt(repayShares, 0);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = stakedLp;
        params.frxUsdAmountToSwap = 0;
        params.repayShares = repayShares;

        uint256 dusdFromLp = stakedLp / 2;
        assertLt(dusdFromLp, DEFAULT_BORROW, "precondition: curve DUSD is insufficient for full debt repay");
        assertEq(borrowToken.balanceOf(address(position)), 0);

        vm.prank(OWNER);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        position.remove(_encodeRemove(params));
    }

    function test_Remove_Normal_RepaysBorrowSharesWhenRepaySharesIsGreaterThanZero() public {
        uint256 repayShares = _marketPosition().borrowShares / 2;
        assertGt(repayShares, 0);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.repayShares = repayShares;

        borrowToken.mint(address(position), DEFAULT_BORROW);
        Position memory marketPositionBefore = _marketPosition();

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition().borrowShares, marketPositionBefore.borrowShares - repayShares);
    }

    function test_Remove_Normal_SkipsCollateralWithdrawalWhenCollateralAmountIsZero() public {
        uint256 collateralBefore = _marketPosition().collateralAssets;

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.collateralAmountToWithdraw = 0;

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(_marketPosition().collateralAssets, collateralBefore);
    }

    function test_Remove_Normal_WithdrawsCollateralAmountToOwner() public {
        uint256 collateralWithdraw = 1_000e18;

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.collateralAmountToWithdraw = collateralWithdraw;

        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);
        uint256 marketCollateralBefore = _marketPosition().collateralAssets;

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(_marketPosition().collateralAssets, marketCollateralBefore - uint128(collateralWithdraw));
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + collateralWithdraw);
    }

    function test_Remove_Normal_WithdrawsFullCollateralWhenExplicitAmountProvided() public {
        MintCurveConvexPosition fresh = _createPosition(OWNER);
        _mintCollateralFor(address(fresh), DEFAULT_COLLATERAL);
        (uint256 minFrxOut, uint256 minLpOut) = _unusedAddMinOuts();
        vm.prank(OWNER);
        fresh.add(_encodeAdd(_addParams(DEFAULT_COLLATERAL, 0, 0, minFrxOut, minLpOut)));

        uint256 fullCollateral = _marketPosition(address(fresh)).collateralAssets;
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.collateralAmountToWithdraw = fullCollateral;

        vm.prank(OWNER);
        fresh.remove(_encodeRemove(params));

        assertEq(_marketPosition(address(fresh)).collateralAssets, 0);
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + fullCollateral);
    }

    function test_Remove_Normal_OnSuccessfulCompletion() public {
        uint256 repayShares = _marketPosition().borrowShares / 5;
        if (repayShares == 0) repayShares = 1;
        uint256 collateralWithdraw = 1_000e18;
        uint256 fraxAmount = 50e18;

        borrowToken.mint(address(position), DEFAULT_BORROW);
        frxUsd.mint(address(position), fraxAmount);
        collateralToken.mint(address(position), 1e18);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.convexLpAmount = WITHDRAW_LP;
        params.frxUsdAmountToSwap = fraxAmount;
        params.repayShares = repayShares;
        params.collateralAmountToWithdraw = collateralWithdraw;

        uint256 ownerDusdBefore = borrowToken.balanceOf(OWNER);
        uint256 ownerFrxBefore = frxUsd.balanceOf(OWNER);
        uint256 ownerCollateralBefore = collateralToken.balanceOf(OWNER);
        uint256 borrowSharesBefore = _marketPosition().borrowShares;
        uint256 marketCollateralBefore = _marketPosition().collateralAssets;

        vm.recordLogs();
        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertTrue(_logsContainRemovePosition(WITHDRAW_LP, collateralWithdraw, repayShares));

        assertEq(convexRewardPool.lastWithdrawAmount(), WITHDRAW_LP);
        assertEq(curvePool.lastLpRemoved(), WITHDRAW_LP);
        assertLt(_marketPosition().borrowShares, borrowSharesBefore);
        assertEq(_marketPosition().collateralAssets, marketCollateralBefore - uint128(collateralWithdraw));
        assertGt(borrowToken.balanceOf(OWNER), ownerDusdBefore);
        assertGt(frxUsd.balanceOf(OWNER), ownerFrxBefore);
        assertEq(collateralToken.balanceOf(OWNER), ownerCollateralBefore + collateralWithdraw + 1e18);
    }

    function test_Remove_EmergencyUnwindLp_SkipsLpUnwindWhenConvexLpAmountIsZero() public {
        borrowToken.mint(address(position), 10e18);
        frxUsd.mint(address(position), 20e18);
        curvePool.mint(address(position), 5e18);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.mode = MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP;
        params.convexLpAmount = 0;

        uint256 withdrawCallsBefore = convexRewardPool.withdrawCallCount();
        uint256 removeLiquidityCallsBefore = curvePool.removeLiquidityCallCount();
        Position memory marketPositionBefore = _marketPosition();
        uint256 swapCallsBefore = swapTarget.swapCallCount();

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(convexRewardPool.withdrawCallCount(), withdrawCallsBefore);
        assertEq(curvePool.removeLiquidityCallCount(), removeLiquidityCallsBefore);
        assertEq(borrowToken.balanceOf(OWNER), 10e18);
        assertEq(frxUsd.balanceOf(OWNER), 20e18);
        assertEq(curvePool.balanceOf(OWNER), 5e18);
        _assertNoSwapAndMarketPositionUnchanged(marketPositionBefore, swapCallsBefore);
    }

    function test_Remove_EmergencyUnwindLp_WhenMintMarketPositionIsHealthy() public {
        _fundRewards(30e18, 15e18);
        borrowToken.mint(address(position), 10e18);
        frxUsd.mint(address(position), 20e18);
        curvePool.mint(address(position), 5e18);

        Position memory marketPositionBefore = _marketPosition();
        uint256 swapCallsBefore = swapTarget.swapCallCount();

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.mode = MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP;
        params.convexLpAmount = WITHDRAW_LP;

        vm.recordLogs();
        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertTrue(convexRewardPool.lastWithdrawClaimRewards());
        assertEq(curvePool.lastLpRemoved(), WITHDRAW_LP);
        assertGt(borrowToken.balanceOf(OWNER), 0);
        assertGt(frxUsd.balanceOf(OWNER), 0);
        assertGt(curvePool.balanceOf(OWNER), 0);
        assertGt(crv.balanceOf(OWNER), 0);
        assertGt(cvx.balanceOf(OWNER), 0);
        assertTrue(_logsContainClaimRewards());
        _assertNoSwapAndMarketPositionUnchanged(marketPositionBefore, swapCallsBefore);
    }

    function test_Remove_EmergencyUnwindLp_WhenMarketCollateralIsZero() public {
        _governanceLiquidatePosition(address(position));
        assertEq(_marketPosition().collateralAssets, 0);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.mode = MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP;
        params.convexLpAmount = WITHDRAW_LP;

        Position memory marketPositionBefore = _marketPosition();
        uint256 swapCallsBefore = swapTarget.swapCallCount();

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertEq(convexRewardPool.lastWithdrawAmount(), WITHDRAW_LP);
        assertEq(curvePool.lastLpRemoved(), WITHDRAW_LP);
        _assertNoSwapAndMarketPositionUnchanged(marketPositionBefore, swapCallsBefore);
    }

    function test_Remove_EmergencyUnwindLp_WhenMarketDebtRemainsWhileCollateralIsImpaired() public {
        uint128 remainingDebt = _marketPosition().borrowShares;
        _zeroMarketCollateralKeepDebt(address(position));
        assertEq(_marketPosition().collateralAssets, 0);
        assertEq(_marketPosition().borrowShares, remainingDebt);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.mode = MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP;
        params.convexLpAmount = WITHDRAW_LP;

        Position memory marketPositionBefore = _marketPosition();
        uint256 swapCallsBefore = swapTarget.swapCallCount();

        vm.prank(OWNER);
        position.remove(_encodeRemove(params));

        assertGt(borrowToken.balanceOf(OWNER), 0);
        _assertNoSwapAndMarketPositionUnchanged(marketPositionBefore, swapCallsBefore);
    }

    function test_Remove_WhenCallerIsAuthorizedSpender() public {
        _authorizeSpender(OWNER, AUTHORIZED_SPENDER);

        MintCurveConvexRemoveParams memory params = _defaultRemoveParams();
        params.mode = MintCurveConvexRemoveMode.EMERGENCY_UNWIND_LP;
        params.convexLpAmount = WITHDRAW_LP;

        Position memory marketPositionBefore = _marketPosition();
        uint256 swapCallsBefore = swapTarget.swapCallCount();

        vm.prank(AUTHORIZED_SPENDER);
        position.remove(_encodeRemove(params));

        assertEq(convexRewardPool.lastWithdrawAmount(), WITHDRAW_LP);
        _assertNoSwapAndMarketPositionUnchanged(marketPositionBefore, swapCallsBefore);
    }

    function _assertNoSwapAndMarketPositionUnchanged(Position memory marketPositionBefore, uint256 swapCallsBefore)
        internal
        view
    {
        assertEq(swapTarget.swapCallCount(), swapCallsBefore);
        assertEq(_marketPosition().collateralAssets, marketPositionBefore.collateralAssets);
        assertEq(_marketPosition().borrowShares, marketPositionBefore.borrowShares);
    }

    function _logsContainClaimRewards() internal returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.ClaimRewards.selector) {
                return true;
            }
        }
        return false;
    }

    function _logsContainRemovePosition(uint256 convexLpRemoved, uint256 collateralWithdrawn, uint256 debtSharesRepaid)
        internal
        returns (bool)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IMintCurveConvexPositionEvents.RemovePosition.selector) {
                (
                    MintCurveConvexRemoveMode mode,
                    uint256 loggedConvexLpRemoved,
                    uint256 loggedCollateralWithdrawn,
                    uint256 loggedDebtSharesRepaid
                ) = abi.decode(logs[i].data, (MintCurveConvexRemoveMode, uint256, uint256, uint256));
                return mode == MintCurveConvexRemoveMode.NORMAL && loggedConvexLpRemoved == convexLpRemoved
                    && loggedCollateralWithdrawn == collateralWithdrawn && loggedDebtSharesRepaid == debtSharesRepaid;
            }
        }
        return false;
    }
}
