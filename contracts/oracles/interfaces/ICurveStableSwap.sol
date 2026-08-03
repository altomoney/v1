// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @title Curve StableSwap NG Pool Interface
///
/// @notice Minimal interface used to validate and inspect a two-coin Curve
/// StableSwap NG pool.
interface ICurveStableSwap {
    /// @notice Returns the number of coins in the pool.
    ///
    /// @return coinCount Number of coins in the pool.
    function N_COINS() external view returns (uint256 coinCount);

    /// @notice Returns the coin registered at `index`.
    ///
    /// @param index Coin index to query.
    ///
    /// @return coin Address registered at `index`.
    function coins(uint256 index) external view returns (address coin);

    /// @notice Returns the current amplification coefficient, including Curve's
    /// precision factor.
    ///
    /// @return preciseA Current precise amplification coefficient.
    function A_precise() external view returns (uint256 preciseA);

    /// @notice Returns the target amplification coefficient.
    ///
    /// @return futureA Target precise amplification coefficient.
    function future_A() external view returns (uint256 futureA);

    /// @notice Returns the EMA averaging time configured by the pool.
    ///
    /// @return maExpTime EMA exponential time constant, in seconds.
    function ma_exp_time() external view returns (uint256 maExpTime);

    /// @notice Returns Curve's packed price-oracle and invariant update timestamps.
    ///
    /// @return packedTimestamps Price timestamp in the low 128 bits and invariant
    /// timestamp in the high 128 bits.
    function ma_last_time() external view returns (uint256 packedTimestamps);

    /// @notice Returns the instantaneous AMM state price for `index`.
    ///
    /// @param index Price index, where zero represents coin 1 quoted in coin 0.
    ///
    /// @return statePriceWad Instantaneous state price using 1e18 precision.
    function get_p(uint256 index) external view returns (uint256 statePriceWad);

    /// @notice Returns the last state price stored by the pool for `index`.
    ///
    /// @param index Price index, where zero represents coin 1 quoted in coin 0.
    ///
    /// @return statePriceWad Stored state price using 1e18 precision.
    function last_price(uint256 index) external view returns (uint256 statePriceWad);

    /// @notice Returns the EMA value stored at the pool's last oracle update for `index`.
    ///
    /// @param index Price index, where zero represents coin 1 quoted in coin 0.
    ///
    /// @return emaPriceWad Stored EMA price using 1e18 precision.
    function ema_price(uint256 index) external view returns (uint256 emaPriceWad);

    /// @notice Returns the EMA price for `index`, projected to the current timestamp.
    ///
    /// @param index Price index, where zero represents coin 1 quoted in coin 0.
    ///
    /// @return emaPriceWad Projected EMA price using 1e18 precision.
    function price_oracle(uint256 index) external view returns (uint256 emaPriceWad);

    /// @notice Returns the pool's current token balances in coin order.
    ///
    /// @return balances Current pool balances, excluding accrued admin fees.
    function get_balances() external view returns (uint256[] memory balances);
}
