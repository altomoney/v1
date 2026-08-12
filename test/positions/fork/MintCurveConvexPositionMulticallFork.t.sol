// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import {MintCurveConvexPositionForkCommon} from "./MintCurveConvexPositionForkCommon.t.sol";
import {MintCurveConvexPosition} from "@alto/positions/MintCurveConvexPosition.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Position} from "@alto/lending/interfaces/IMarket.sol";
import {CRV_TOKEN_MAINNET, CVX_TOKEN_MAINNET, WETH_MAINNET} from "@alto/deployments/ethereum-mainnet/Constants.sol";

/// @dev Fork coverage for batching position actions atomically through multicall.
contract MintCurveConvexPositionMulticallForkTest is MintCurveConvexPositionForkCommon {
    uint256 internal constant REWARD_ACCRUAL_BLOCKS = 100_000;
    uint256 internal constant REWARD_ACCRUAL_PERIOD = 14 days;

    function test_Multicall_OpensPositionAtomically_AddCollateralThenBorrowAndDeposit() public {
        _fundUserWeth(COLLATERAL_WETH);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (COLLATERAL_WETH));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.borrowAndDepositToLp, (BORROW_ASSETS, 0));

        vm.prank(user);
        position.multicall(calls);

        assertEq(_marketPosition(address(position)).collateralAssets, COLLATERAL_WETH);
        assertGt(_marketPosition(address(position)).borrowShares, 0);
        // One-sided DUSD deposit into a ~1:1 stable pool mints LP within 0.5% of the DUSD borrowed.
        assertApproxEqRel(_stakedLpBalance(), BORROW_ASSETS, 0.005e18);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), 0);
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
    }

    function test_Multicall_StacksTwoCollateralAddsThenBorrows() public {
        _fundUserWeth(COLLATERAL_WETH);
        uint256 firstChunk = COLLATERAL_WETH / 3;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (firstChunk));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.addCollateral, (COLLATERAL_WETH - firstChunk));
        calls[2] = abi.encodeCall(MintCurveConvexPosition.borrowAndDepositToLp, (BORROW_ASSETS, 0));

        vm.prank(user);
        position.multicall(calls);

        assertEq(_marketPosition(address(position)).collateralAssets, COLLATERAL_WETH);
        assertGt(_marketPosition(address(position)).borrowShares, 0);
        assertGt(_stakedLpBalance(), 0);
    }

    function test_Multicall_ClosesPositionAtomically_RepayAllRemoveCollateralThenWithdrawAndClaim() public {
        uint256 stakedLp = _openBorrowPosition();
        // Pin the oracle price before warping so removeCollateral's solvency check survives the warp.
        _pinCollateralOraclePrice();
        _advanceChainForRewards();

        Position memory before = _marketPosition(address(position));
        uint256 repayShares = before.borrowShares;
        uint256 collateral = before.collateralAssets;

        // Repay runs before any LP unwind, so the full debt must be funded from the owner.
        // Extra buffer covers interest accrued over the reward window that `_borrowAssetsForShares` (un-accrued) omits.
        _fundUserDusd(_borrowAssetsForShares(repayShares) + 100 ether);

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.repay, (repayShares));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.removeCollateral, (collateral));
        // Withdraw the full LP stake and claim rewards in the same call.
        calls[2] = abi.encodeCall(MintCurveConvexPosition.withdrawFromLpAndRepay, (stakedLp, 0, 0, true));

        vm.prank(user);
        position.multicall(calls);

        assertEq(_stakedLpBalance(), 0);
        assertEq(_marketPosition(address(position)).borrowShares, 0);
        assertEq(_marketPosition(address(position)).collateralAssets, 0);
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), collateral, "collateral returned to owner");
        assertGt(_rewardTokenBalanceGained(), 0, "rewards claimed to owner");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
    }

    function test_Multicall_DeleveragesPartially_RepayThenRemoveCollateral() public {
        uint256 stakedLp = _openBorrowPosition();
        Position memory before = _marketPosition(address(position));
        uint256 repayShares = before.borrowShares / 2;
        assertGt(repayShares, 0);
        uint256 collateralWithdraw = COLLATERAL_WETH / 4;

        _fundUserDusd(_borrowAssetsForShares(repayShares) + 1 ether);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.repay, (repayShares));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.removeCollateral, (collateralWithdraw));

        vm.prank(user);
        position.multicall(calls);

        assertEq(_marketPosition(address(position)).borrowShares, before.borrowShares - repayShares);
        assertEq(
            _marketPosition(address(position)).collateralAssets, before.collateralAssets - uint128(collateralWithdraw)
        );
        assertEq(_stakedLpBalance(), stakedLp, "repay/remove leave the LP stake untouched");
        assertEq(IERC20(WETH_MAINNET).balanceOf(user), collateralWithdraw);
    }

    function test_Multicall_UnwindsHalfLpAndClaimsRewardsInOneBatch() public {
        uint256 stakedLp = _openBorrowPosition();
        _advanceChainForRewards();

        uint256 partialLp = stakedLp / 2;
        uint256 userDusdBefore = IERC20(DUSD_MAINNET).balanceOf(user);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(MintCurveConvexPosition.withdrawFromLpAndRepay, (partialLp, 0, 0, false));
        calls[1] = abi.encodeCall(MintCurveConvexPosition.claimRewards, ());

        vm.prank(user);
        position.multicall(calls);

        assertEq(_stakedLpBalance(), stakedLp - partialLp);
        assertGt(IERC20(DUSD_MAINNET).balanceOf(user), userDusdBefore, "unwound DUSD swept to owner");
        assertGt(_rewardTokenBalanceGained(), 0, "rewards claimed to owner");
        assertEq(IERC20(DUSD_MAINNET).balanceOf(address(position)), 0);
    }

    function _advanceChainForRewards() internal {
        vm.roll(block.number + REWARD_ACCRUAL_BLOCKS);
        vm.warp(block.timestamp + REWARD_ACCRUAL_PERIOD);
    }

    /// @dev Sum of the two configured base Convex reward-token balances held by the owner.
    function _rewardTokenBalanceGained() internal view returns (uint256) {
        return IERC20(CRV_TOKEN_MAINNET).balanceOf(user) + IERC20(CVX_TOKEN_MAINNET).balanceOf(user);
    }
}
