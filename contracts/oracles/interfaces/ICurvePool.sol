// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title ICurvePool
/// @author Curve Finance
/// @notice Interface for the Curve NG pool
interface ICurvePool {
    // @notice Getter for the exponential moving-average time for the price oracle
    function ma_exp_time() external view returns (uint256);

    // @notice function to calculate the exponential moving average (EMA) price for the coin at (index+1)
    // with regard to the coin at index 0.
    // @dev The calculation is based on the last spot value (last_price), the last ma value (ema_price),
    // the moving average time window (ma_exp_time), and on the difference between the current timestamp (block.timestamp)
    // and the timestamp when the ma oracle was last updated (unpacks from the first value of ma_last_time).
    function price_oracle(uint256 index) external view returns (uint256);

    // @notice Getter for the last time the exponential moving-average oracle of coin prices or the D invariant was updated
    // @dev The value is packed into a uint256 where the first 128 bits are the timestamp of last update of prices
    //  and the last 128 bits represents the timestamp of last update of the D invariant.
    function ma_last_time() external view returns (uint256);

    // @notice Calculates the pool's balances excluding the admin's balances.
    function get_balances() external view returns (uint256[] memory);

    // @notice Getter for the number of coins in the pool
    function N_COINS() external view returns (uint256);
}
