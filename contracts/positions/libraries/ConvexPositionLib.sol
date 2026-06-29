// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IConvexBooster, IConvexRewardPool} from "../interfaces/IConvex.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ConvexPositionLib
/// @notice Internal helpers for staking curve LP tokens to convex and withdrawing them from convex
library ConvexPositionLib {
    using SafeERC20 for IERC20;

    /// @notice Stakes Curve LP through the Convex booster.
    /// @dev Staking curve LP tokens will give receipt tokens which will always be staked again to the rewardPool
    /// @param booster The address of the convex booster contract
    /// @param poolId The id of the curve pool to stake the LP tokens to
    /// @param lpToken The address of the curve LP token
    /// @param lpAmount The amount of curve LP tokens to stake
    function stake(address booster, uint256 poolId, address lpToken, uint256 lpAmount) internal {
        if (lpAmount == 0) return;

        IERC20(lpToken).forceApprove(booster, lpAmount);
        // toStake flag is always true
        IConvexBooster(booster).deposit(poolId, lpAmount, true);
        IERC20(lpToken).forceApprove(booster, 0);
    }

    /// @notice Withdraws staked LP from the Convex reward pool and transfer curve LP tokens to the caller.
    /// @dev Unwrapping the convex receipt tokens will give the curve LP tokens to the caller
    /// @param rewardPool The address of the convex reward pool contract
    /// @param lpAmount The amount of convex receipt tokens to withdraw
    /// @param claimRewards Whether to claim rewards from the convex reward pool
    function withdraw(address rewardPool, uint256 lpAmount, bool claimRewards) internal {
        IConvexRewardPool(rewardPool).withdrawAndUnwrap(lpAmount, claimRewards);
    }

    /// @notice Claims CRV/CVX rewards from the Convex reward pool to the caller.
    /// @dev This will transfer the CRV/CVX rewards to the caller
    function claimRewards(address rewardPool) internal {
        IConvexRewardPool(rewardPool).getReward();
    }
}
