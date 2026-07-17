// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ICurveStablePool
/// @notice Minimal Curve stableswap-ng interface for one-sided liquidity operations.
interface ICurveStablePool {
    /// @notice Address of the i-th coin in the pool.
    /// @dev The indexing starts from 0 for the first coin.
    function coins(uint256 i) external view returns (address);

    /// @notice Number of coins in the pool.
    function N_COINS() external view returns (uint256);

    /// @notice Adds liquidity to the pool.
    /// @param amounts The amount of each coin to deposit (0 for a one-sided deposit).
    /// @param minMintAmount The minimum amount of LP tokens to receive.
    /// @return Amount of LP tokens received by depositing
    /// @dev LP tokens are minted to `msg.sender`.
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount) external returns (uint256);

    /// @notice Withdraw a single coin from the pool
    /// @param burnAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @param minReceived Minimum amount of coin to receive
    /// @return Amount of coin received
    /// @dev The withdrawn coin is sent to `msg.sender`.
    function remove_liquidity_one_coin(uint256 burnAmount, int128 i, uint256 minReceived) external returns (uint256);
}
