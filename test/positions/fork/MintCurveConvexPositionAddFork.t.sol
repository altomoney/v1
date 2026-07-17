// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMintCurveConvexPositionEvents} from "@alto/positions/interfaces/IMintCurveConvexPosition.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {
    CONVEX_BOOSTER_MAINNET,
    FRXUSD_DUSD_CURVE_POOL_MAINNET,
    WETH_MAINNET
} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Fork coverage for addCollateral, removeCollateral and borrowAndDepositToLp.
contract MintCurveConvexPositionAddForkTest is MintCurveConvexPositionForkCommon {
    function test_AddCollateral_PullsWethFromOwnerAndPostsToMarket() public {
        uint256 collateral = 10 ether;
        _fundUserWeth(collateral);

        Position memory before = _marketPosition(address(position));

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.CollateralAdded(collateral);

        vm.prank(user);
        position.addCollateral(collateral);

        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets + uint128(collateral));
        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares);
        assertEq(_stakedLpBalance(), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);
        // Market allowance is reset to zero after the deposit.
        assertEq(IERC20(WETH_MAINNET).allowance(address(position), WETH_MINT_MARKET_MAINNET), 0);
    }

    function test_RemoveCollateral_WithdrawsWethToOwner() public {
        _addCollateral(COLLATERAL_WETH);

        uint256 withdrawAmount = COLLATERAL_WETH / 4;
        Position memory before = _marketPosition(address(position));

        vm.expectEmit(false, false, false, true, address(position));
        emit IMintCurveConvexPositionEvents.CollateralRemoved(withdrawAmount);

        vm.prank(user);
        position.removeCollateral(withdrawAmount);

        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets - uint128(withdrawAmount));
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), withdrawAmount);
        assertEq(IERC20(WETH_MAINNET).balanceOf(address(position)), 0);
    }

    function test_BorrowAndDepositToLp_BorrowsDusdSuppliesOneSidedAndStakes() public {
        _addCollateral(COLLATERAL_WETH);

        Position memory before = _marketPosition(address(position));

        vm.expectEmit(false, false, false, false, address(position));
        emit IMintCurveConvexPositionEvents.Deposited(BORROW_ASSETS, 0);

        vm.prank(user);
        position.borrowAndDepositToLp(BORROW_ASSETS, 0);

        assertGt(_marketPosition(address(position)).borrowShares, before.borrowShares);
        assertEq(_marketPosition(address(position)).collateralAssets, before.collateralAssets);
        // One-sided DUSD deposit into a ~1:1 stable pool mints LP within 0.5% of the DUSD borrowed.
        assertApproxEqRel(_stakedLpBalance(), BORROW_ASSETS, 0.005e18);

        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
        assertEq(IERC20(DUSD_MAINNET).allowance(address(position), FRXUSD_DUSD_CURVE_POOL_MAINNET), 0);
        assertEq(IERC20(FRXUSD_DUSD_CURVE_POOL_MAINNET).allowance(address(position), CONVEX_BOOSTER_MAINNET), 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), 0);
    }

    function test_BorrowAndDepositToLp_StakedLpIsWithinSlippageOfBorrow() public {
        _openBorrowPosition();

        // One-sided DUSD deposit into a ~1:1 stable pool mints LP close to the DUSD value supplied.
        uint256 stakedLp = _stakedLpBalance();
        assertGe(stakedLp, _applySlippage(BORROW_ASSETS));
        assertLe(stakedLp, _addSlippage(BORROW_ASSETS));
    }
}
