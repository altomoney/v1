// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title ModuleCurve
/// @author Pearl Labs
/// @notice Module contract that is used to read from Curve pools
contract ModuleCurve {
    error ModuleCurveInvalidRate();
    error ModuleCurveInvalidInput();

    /// @notice Gets a quote for an amount of in-currency using Curve TWAP and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount to convert in the out-currency
    /// @param pool Curve pool to query
    /// @param coinIndex Index of the coin to query
    /// @param isMultiplied Whether the rate corresponding to the Curve pool should be multiplied or divided
    /// @param inDecimals Number of decimals of the in-currency
    /// @param outDecimals Number of decimals of the out-currency
    /// @param minMaExpTime Minimum time for the MA exponential
    /// @param stalePeriod Stale period for the Curve pool
    /// @return The value of the `quoteAmount` expressed in out-currency
    function readCurvePool(
        uint256 quoteAmount,
        ICurvePool pool,
        uint256 coinIndex,
        uint8 isMultiplied,
        uint8 inDecimals,
        uint8 outDecimals,
        uint256 minMaExpTime,
        uint256 stalePeriod
    ) public view returns (uint256) {
        uint256 packedLastUpdateTime = pool.ma_last_time();
        // The value is packed into a uint256 where the first 128 bits are the timestamp of last update of prices
        //  and the last 128 bits represents the timestamp of last update of the D invariant.
        uint256 lastMaUpdateTime = packedLastUpdateTime >> 128;

        // checks whether the prices are stale
        if (block.timestamp - lastMaUpdateTime > stalePeriod) {
            revert ModuleCurveInvalidRate();
        }

        // checks whether the minimum time for the MA exponential is met
        if (pool.ma_exp_time() < minMaExpTime) {
            revert ModuleCurveInvalidRate();
        }

        uint256 price = pool.price_oracle(coinIndex);

        // checks whether the rate should be multiplied or divided
        // quote amount decimals will be decimals of in-currency
        if (isMultiplied == 1) {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, price, MATH_PRECISION, false);
        } else {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, MATH_PRECISION, price, false);
        }

        // converts the quoteAmount to the out-currency decimals
        quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, (10 ** outDecimals), (10 ** inDecimals), false);
        return (quoteAmount);
    }

    /// @notice Validates the parameters for the Curve pool during initialization or updates
    /// @param pool Curve pool to query
    /// @param coinIndex Index of the coin to query
    /// @param isMultiplied Whether the rate corresponding to the Curve pool should be multiplied or divided
    /// @param inDecimals Number of decimals of the in-currency
    /// @param outDecimals Number of decimals of the out-currency
    /// @param minMaExpTime Minimum time for the MA exponential
    /// @param stalePeriod Stale period for the Curve pool
    function _validateCurveParams(
        ICurvePool pool,
        uint256 coinIndex,
        uint8 isMultiplied,
        uint8 inDecimals,
        uint8 outDecimals,
        uint256 minMaExpTime,
        uint256 stalePeriod
    ) internal view {
        if (address(pool) == address(0) || inDecimals == 0 || outDecimals == 0 || minMaExpTime == 0 || stalePeriod == 0)
        {
            revert ModuleCurveInvalidInput();
        }

        // total number of coins in curve pool
        uint256 nCoins = pool.N_COINS();

        // coin index is used to get the price of coin at (coinIndex + 1) with respect to coin at index 0
        if (coinIndex >= nCoins - 1) {
            revert ModuleCurveInvalidInput();
        }

        if (isMultiplied != 0 && isMultiplied != 1) {
            revert ModuleCurveInvalidInput();
        }

        // checks whether the minimum time for the MA exponential is met
        if (pool.ma_exp_time() < minMaExpTime) {
            revert ModuleCurveInvalidInput();
        }
    }
}
