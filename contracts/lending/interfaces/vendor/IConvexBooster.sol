// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Convex Booster Interface
///
/// @notice Minimal Ethereum Convex Booster surface used by the credit line.
interface IConvexBooster {
    function poolInfo(uint256 pid)
        external
        view
        returns (address lpToken, address depositToken, address gauge, address rewardPool, address stash, bool shutdown);

    function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);
}
