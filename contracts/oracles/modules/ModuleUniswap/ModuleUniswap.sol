// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleMath} from "./OracleMath.sol";
import {UniswapNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleUniswap
/// @author Pearl Labs
/// @dev This contract is used to read from Uniswap pools
contract ModuleUniswap is OracleMath {
    error ModuleUniswapInvalidInput();

    /// @notice Gets a quote for an amount of in-currency using UniswapV3 TWAP and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount to convert in the out-currency
    /// @param config Uniswap node configuration
    /// @return The value of the `quoteAmount` expressed in out-currency
    function readUniswapPool(uint256 quoteAmount, UniswapNode memory config) public view returns (uint256) {
        uint32[] memory secondAgos = new uint32[](2);

        secondAgos[0] = config.twapPeriod;
        secondAgos[1] = 0;

        (int56[] memory tickCumulatives,) = config.pool.observe(secondAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int32(config.twapPeriod));

        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(int32(config.twapPeriod)) != 0)) {
            timeWeightedAverageTick--;
        }

        // Computing the `quoteAmount` from the ticks obtained from Uniswap
        return _getQuoteAtTick(timeWeightedAverageTick, quoteAmount, config.multiplied);
    }

    /// @notice Validates the parameters for the Uniswap pool during initialization or updates
    /// @param config Uniswap node configuration
    function _validateUniswapParams(UniswapNode memory config) internal pure {
        if (address(config.pool) == address(0) || config.twapPeriod == 0) {
            revert ModuleUniswapInvalidInput();
        }

        if (config.multiplied != 0 && config.multiplied != 1) {
            revert ModuleUniswapInvalidInput();
        }
    }
}
