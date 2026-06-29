// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ICurveStablePool
/// @notice Minimal Curve stable pool interface for liquidity operations.
interface ICurveStablePool {
    // @notice get the address of the i-th coin
    function coins(uint256 i) external view returns (address);

    // @notice get the number of coins in the curve Pool
    function N_COINS() external view returns (uint256);

    // @notice add liquidity to the pool
    // @param amounts the amounts of each coin to deposit
    // @param minMintAmount the minimum amount of LP tokens to receive
    // @param receiver the address to receive the LP tokens
    // @return the amount of LP tokens received
    function add_liquidity(uint256[] calldata amounts, uint256 minMintAmount, address receiver)
        external
        returns (uint256);

    // @notice remove liquidity from the pool
    // @param amount the amount of LP tokens to remove
    // @param minAmounts the minimum amounts of each coin to receive
    // @return the amounts of each coin received
    function remove_liquidity(uint256 amount, uint256[] calldata minAmounts) external returns (uint256[] memory);
}
