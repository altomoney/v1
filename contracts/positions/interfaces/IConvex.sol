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

    /// @notice The booster's registry entry for a given pool id.
    /// @param pid The Convex pool id to look up.
    /// @return lptoken The Curve LP token staked for this pid.
    /// @return token The Convex deposit/receipt token minted for this pid.
    /// @return gauge The Curve gauge for this pid.
    /// @return crvRewards The reward pool (BaseRewardPool) tracking staked LP and rewards for this pid.
    /// @return stash The extra-rewards stash for this pid.
    /// @return shutdown Whether this pool has been shut down on the booster.
    function poolInfo(uint256 pid)
        external
        view
        returns (address lptoken, address token, address gauge, address crvRewards, address stash, bool shutdown);
}

/// @title IConvexRewardPool
/// @notice Minimal Convex reward pool interface for LP withdrawal.
interface IConvexRewardPool {
    // @notice the Convex pool id this reward pool corresponds to
    function pid() external view returns (uint256);

    // @notice get the balance of the account
    function balanceOf(address account) external view returns (uint256);

    // @notice withdraw the convex LP tokens and unwrap the LP tokens to curve LP tokens
    function withdrawAndUnwrap(uint256 amount, bool claim) external returns (bool);

    // @notice claim the CRV and CVX rewards accumulated by the caller
    function getReward() external returns (bool);
}
