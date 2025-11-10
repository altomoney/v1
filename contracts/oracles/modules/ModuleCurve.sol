// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {CurveNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleCurve
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice Module contract that is used to read from Curve pools
contract ModuleCurve {
    error ModuleCurveInvalidRate();
    error ModuleCurveInvalidInput();

    /// @notice Gets a quote for an amount of in-currency using Curve TWAP and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount to convert in the out-currency
    /// @param config Curve node configuration
    /// @return The value of the `quoteAmount` expressed in out-currency
    function readCurvePool(uint256 quoteAmount, CurveNode memory config) public view returns (uint256) {
        uint256 packedLastUpdateTime = config.pool.ma_last_time();
        // The value is packed into a uint256 where the first 128 bits are the timestamp of last update of prices
        //  and the last 128 bits represents the timestamp of last update of the D invariant.
        uint256 lastMaUpdateTime = packedLastUpdateTime >> 128;

        // checks whether the prices are stale
        if (block.timestamp - lastMaUpdateTime > config.stalePeriod) {
            revert ModuleCurveInvalidRate();
        }

        // checks whether the minimum time for the MA exponential is met
        if (config.pool.ma_exp_time() < config.minMaExpTime) {
            revert ModuleCurveInvalidRate();
        }

        uint256 price = config.pool.price_oracle(config.coinIndex);

        // checks whether the rate should be multiplied or divided
        // quote amount decimals will be decimals of in-currency
        if (config.multiplied == 1) {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, price, MATH_PRECISION, false);
        } else {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, MATH_PRECISION, price, false);
        }

        // converts the quoteAmount to the out-currency decimals
        quoteAmount = FixedPointMath.divideWithRounding(
            quoteAmount, (10 ** config.outDecimals), (10 ** config.inDecimals), false
        );
        return (quoteAmount);
    }

    /// @notice Validates the parameters for the Curve pool during initialization or updates
    /// @param config Curve node configuration
    function _validateCurveParams(CurveNode memory config) internal view {
        if (
            address(config.pool) == address(0) || config.inDecimals == 0 || config.outDecimals == 0
                || config.minMaExpTime == 0 || config.stalePeriod == 0
        ) {
            revert ModuleCurveInvalidInput();
        }

        // total number of coins in curve pool
        uint256 nCoins = config.pool.N_COINS();

        // coin index is used to get the price of coin at (coinIndex + 1) with respect to coin at index 0
        if (config.coinIndex >= nCoins - 1) {
            revert ModuleCurveInvalidInput();
        }

        if (config.multiplied != 0 && config.multiplied != 1) {
            revert ModuleCurveInvalidInput();
        }

        // checks whether the minimum time for the MA exponential is met
        if (config.pool.ma_exp_time() < config.minMaExpTime) {
            revert ModuleCurveInvalidInput();
        }
    }
}
