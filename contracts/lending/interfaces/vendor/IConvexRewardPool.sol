// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Convex Base Reward Pool Interface
/// @notice Minimal Ethereum Convex BaseRewardPool surface used by the credit line.
interface IConvexRewardPool {
    /// @notice Returns the Convex pool identifier
    function pid() external view returns (uint256);

    /// @notice Returns the pool operator
    function operator() external view returns (address);

    /// @notice Returns the staking token
    function stakingToken() external view returns (address);

    /// @notice Returns the primary reward token
    function rewardToken() external view returns (address);

    /// @notice Returns the staked balance of an account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Withdraws and unwraps staked LP tokens
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    /// @notice Claims rewards for an account
    function getReward(address account, bool claimExtras) external returns (bool);
}
