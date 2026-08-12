// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintCurveConvexPositionEvents} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {CRV_TOKEN_MAINNET, CVX_TOKEN_MAINNET, WETH_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Fork coverage for withdrawFromLpAndRepay (LP unwind + optional repay) and repay.
contract MintCurveConvexPositionRemoveForkTest is MintCurveConvexPositionForkCommon {
    uint256 internal constant REWARD_ACCRUAL_BLOCKS = 100_000;
    uint256 internal constant REWARD_ACCRUAL_PERIOD = 14 days;

    uint256 internal stakedLp;

    function setUp() public override {
        super.setUp();
        stakedLp = _openBorrowPosition();
    }

    function test_WithdrawFromLpAndRepay_UnwindsFullLpIntoDusdAndSweepsToOwner() public {
        Position memory before = _marketPosition(address(position));
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Withdrawn(user, stakedLp, 0, 0);

        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp, 0, 0, false);

        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares, "debt unchanged");
        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets, "collateral unchanged");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0, "no residual dusd");
        assertApproxEqRel(dusdReceived, stakedLp, 0.005e18, "one-sided round-trip within 0.5% of staked LP");
    }

    function test_WithdrawFromLpAndRepay_PartialLpUnwind() public {
        uint256 partialLp = stakedLp / 2;
        Position memory before = _marketPosition(address(position));
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.prank(user);
        position.withdrawFromLpAndRepay(partialLp, 0, 0, false);

        uint256 dusdReceived = IERC20(DUSD_MAINNET).balanceOf(user) - userDusdBefore;

        assertEq(_stakedLpBalance(), stakedLp - partialLp);
        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertGe(dusdReceived, _applySlippage(BORROW_ASSETS / 2));
        assertLe(dusdReceived, _addSlippage(BORROW_ASSETS / 2));
    }

    function test_WithdrawFromLpAndRepay_UnwindsLpAndRepaysPartialDebt() public {
        Position memory before = _marketPosition(address(position));
        uint256 repayShares = before.borrowShares / 2;
        assertGt(repayShares, 0);

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.recordLogs();
        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(user, repayShares, 0);

        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp, 0, repayShares, false);

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares - repayShares);
        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0, "leftover dusd swept out");
        // LP unwind (~full borrow) covers the half repay and leaves the remainder for the owner.
        assertGt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore, "surplus dusd returned to owner");
    }

    function test_WithdrawFromLpAndRepay_UnwindsLpAndRepaysAllDebtWithOwnerTopUp() public {
        Position memory before = _marketPosition(address(position));
        uint256 repayShares = before.borrowShares;
        uint256 repayAssets = _borrowAssetsForShares(repayShares);

        // Fund a buffer so any shortfall between the one-sided LP proceeds and the debt is pulled from the owner.
        _fundUserDusd(repayAssets);
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp, 0, repayShares, false);

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0, "debt fully repaid");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertLt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore, "shortfall pulled from owner");
    }

    function test_WithdrawFromLpAndRepay_RepayOnlyThenFullLpWithdraw_RoundTripsDusdWithOwner() public {
        uint256 repayShares = _marketPosition(address(position)).borrowShares;
        uint256 repayAssets = _borrowAssetsForShares(repayShares);

        // Fund the owner so the full debt can be repaid without any LP unwind.
        _fundUserDusd(repayAssets + 1 ether);
        uint256 userDusdBeforeRepay = IERC20(DUSD_MAINNET).balanceOf(user);

        // First tx: no LP withdrawal, repay the full debt -> DUSD is pulled from the owner.
        vm.prank(user);
        position.withdrawFromLpAndRepay(0, 0, repayShares, false);

        uint256 userDusdAfterRepay = IERC20(DUSD_MAINNET).balanceOf(user);
        assertEq(_marketPosition(address(position)).borrowShares, 0, "debt fully repaid");
        assertEq(_stakedLpBalance(), stakedLp, "LP stake untouched by repay-only tx");
        assertLt(userDusdAfterRepay, userDusdBeforeRepay, "dusd taken from owner to repay");

        // Second tx: withdraw the full staked LP with no repay -> proceeds are swept back to the owner.
        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp, 0, 0, false);

        assertEq(_stakedLpBalance(), 0, "full lp unwound");
        assertGt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdAfterRepay, "dusd added back to owner from lp proceeds");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0, "no residual dusd");
    }

    function test_WithdrawFromLpAndRepay_ClaimRewardsTrueTransfersCrvCvxToOwner() public {
        _advanceChainForRewards();

        uint256 userCrvBefore = IERC20(CRV_TOKEN_MAINNET).balanceOf(user);
        uint256 userCvxBefore = IERC20(CVX_TOKEN_MAINNET).balanceOf(user);

        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp / 2, 0, 0, true);

        assertGt(_stakedLpBalance(), 0);
        assertGt(IERC20(CRV_TOKEN_MAINNET).balanceOf(user), userCrvBefore, "crv rewards claimed to owner");
        assertGt(IERC20(CVX_TOKEN_MAINNET).balanceOf(user), userCvxBefore, "cvx rewards claimed to owner");
        assertEq(IERC20(CRV_TOKEN_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(CVX_TOKEN_MAINNET).balanceOf(address(position)), 0);
    }

    function test_WithdrawFromLpAndRepay_AfterGovernanceLiquidation_UnwindsResidualLp() public {
        _governanceLiquidatePosition(address(position));

        Position memory afterLiq = _marketPosition(address(position));
        assertEq(afterLiq.collateralAssets, 0);
        assertEq(afterLiq.borrowShares, 0);
        assertGt(_stakedLpBalance(), 0, "LP survives market liquidation");

        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.prank(user);
        position.withdrawFromLpAndRepay(stakedLp, 0, 0, false);

        assertEq(_stakedLpBalance(), 0);
        assertGt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore, "residual LP recovered to owner");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
    }

    function test_Repay_PullsDusdFromOwnerAndReducesDebt() public {
        Position memory before = _marketPosition(address(position));
        uint256 repayShares = before.borrowShares / 2;
        assertGt(repayShares, 0);

        uint256 repayAssets = _borrowAssetsForShares(repayShares);
        _fundUserDusd(repayAssets + 1 ether);
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        vm.expectEmit(true, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Repaid(user, repayShares, 0);

        vm.prank(user);
        position.repay(repayShares);

        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares - repayShares);
        assertEq(_stakedLpBalance(), stakedLp, "repay does not touch the LP stake");
        assertLt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore, "dusd pulled from owner");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
    }

    function test_Repay_RepaysAllDebt() public {
        uint256 repayShares = _marketPosition(address(position)).borrowShares;
        uint256 repayAssets = _borrowAssetsForShares(repayShares);
        _fundUserDusd(repayAssets + 1 ether);

        vm.prank(user);
        position.repay(repayShares);

        assertEq(_marketPosition(address(position)).borrowShares, 0, "debt fully repaid");
        assertEq(_stakedLpBalance(), stakedLp);
    }

    function _advanceChainForRewards() internal {
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        vm.warp(block.timestamp + REWARD_ACCRUAL_PERIOD);
    }
}
