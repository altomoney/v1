// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IConvexBooster
/// @notice Minimal Convex booster interface for LP staking.
interface IConvexBooster {
    // @notice deposit curve LP tokens to Convex
    // @param pid the pool id of curve pool
    // @param amount the amount of curve LP tokens to deposit
    // @param stake whether to stake the receipt tokens received on depositing the LP tokens
    function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);
}

/// @title IConvexRewardPool
/// @notice Minimal Convex reward pool interface for LP withdrawal.
interface IConvexRewardPool {
    // @notice get the balance of the account
    function balanceOf(address account) external view returns (uint256);

    // @notice withdraw the convex LP tokens and unwrap the LP tokens to curve LP tokens
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    // @notice claim the CRV and CVX rewards accumulated by the caller
    function getReward() external returns (bool);
}
