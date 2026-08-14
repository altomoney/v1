// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Convex Base Reward Pool Interface
///
/// @notice Minimal Ethereum Convex BaseRewardPool surface used by the credit line.
interface IConvexRewardPool {
    function pid() external view returns (uint256);
    function operator() external view returns (address);
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);
    function getReward(address account, bool claimExtras) external returns (bool);
}
