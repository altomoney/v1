// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @title Curve StableSwap NG Pool Base Interface
/// @notice Pool identity used by Curve oracle consumers.
interface ICurveStableSwapNGBase {
    /// @notice Returns the number of coins in the pool.
    function N_COINS() external view returns (uint256 coinCount);

    /// @notice Returns the coin registered at `index`.
    function coins(uint256 index) external view returns (address coin);
}

/// @title Curve StableSwap NG Oracle Interface
/// @notice Read-only pool surface used by Alto's Curve oracle consumers.
interface ICurveStableSwapNGOracle is ICurveStableSwapNGBase {
    /// @notice Returns the current amplification coefficient, including Curve's precision factor.
    function A_precise() external view returns (uint256 preciseA);

    /// @notice Returns the target amplification coefficient.
    function future_A() external view returns (uint256 futureA);

    /// @notice Returns the EMA averaging time configured by the pool.
    function ma_exp_time() external view returns (uint256 maExpTime);

    /// @notice Returns Curve's packed price-oracle and invariant update timestamps.
    function ma_last_time() external view returns (uint256 packedTimestamps);

    /// @notice Returns the instantaneous AMM state price for `index`.
    function get_p(uint256 index) external view returns (uint256 statePriceWad);

    /// @notice Returns the last state price stored by the pool for `index`.
    function last_price(uint256 index) external view returns (uint256 statePriceWad);

    /// @notice Returns the EMA value stored at the pool's last oracle update for `index`.
    function ema_price(uint256 index) external view returns (uint256 emaPriceWad);

    /// @notice Returns the EMA price for `index`, projected to the current timestamp.
    function price_oracle(uint256 index) external view returns (uint256 emaPriceWad);

    /// @notice Returns the pool's current token balances in coin order.
    function get_balances() external view returns (uint256[] memory balances);
}
