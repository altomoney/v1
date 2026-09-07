// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Convex Booster Interface
/// @notice Minimal Ethereum Convex Booster surface used by the credit line.
interface IConvexBooster {
    /// @notice Returns the configuration for a Convex pool
    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, address depositToken, address gauge, address rewardPool, address stash, bool shutdown);

    /// @notice Deposits LP tokens into a Convex pool
    function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);
}
