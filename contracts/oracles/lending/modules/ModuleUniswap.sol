// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleMath} from "@alto/oracles/external/OracleMath.sol";

/// @title ModuleUniswap
/// @author Pearl Labs
/// @dev This contract is used to read from Uniswap pools
contract ModuleUniswap is OracleMath {
    error ModuleUniswapInvalidInput();

    /// @notice Gets a quote for an amount of in-currency using UniswapV3 TWAP and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount to convert in the out-currency
    /// @param pool UniswapV3 pool to query
    /// @param isUniMultiplied Whether the rate corresponding to the Uniswap pool should be multiplied or divided
    /// @param twapPeriod Time weighted average window, it is common for all Uniswap pools
    /// @return The value of the `quoteAmount` expressed in out-currency
    function readUniswapPool(uint256 quoteAmount, IUniswapV3Pool pool, uint8 isUniMultiplied, uint32 twapPeriod)
        public
        view
        returns (uint256)
    {
        uint32[] memory secondAgos = new uint32[](2);

        secondAgos[0] = twapPeriod;
        secondAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pool.observe(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int32(twapPeriod));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(twapPeriod)) != 0)) {
            timeWeightedAverageTick--;
        }

        // Computing the `quoteAmount` from the ticks obtained from Uniswap
        return _getQuoteAtTick(timeWeightedAverageTick, quoteAmount, isUniMultiplied);
    }

    /// @notice Validates the parameters for the Uniswap pool during initialization or updates
    /// @param pool Uniswap pool to query
    /// @param isUniMultiplied Whether the rate corresponding to the Uniswap pool should be multiplied or divided
    /// @param twapPeriod Time weighted average window
    function _validateUniswapParams(IUniswapV3Pool pool, uint8 isUniMultiplied, uint32 twapPeriod) internal pure {
        if (address(pool) == address(0) || twapPeriod == 0) {
            revert ModuleUniswapInvalidInput();
        }

        if (isUniMultiplied != 0 && isUniMultiplied != 1) {
            revert ModuleUniswapInvalidInput();
        }
    }
}
