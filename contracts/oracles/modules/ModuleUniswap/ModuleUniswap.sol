// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleMath} from "./OracleMath.sol";
import {UniswapNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleUniswap
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice Utility contract used to read from Uniswap V3 pools
contract ModuleUniswap is OracleMath {
    error ModuleUniswapInvalidInput();

    /// @notice Gets a quote for an amount of input currency and returns the output currency
    /// @param quoteAmount The input currency amount to get the price of in output currency
    /// @param config Uniswap configuration
    /// @return The value of the `quoteAmount` in output currency
    /// @dev ROUNDING: This function uses floor division (rounds down)
    /// @dev APPROPRIATE USES:
    ///      - Pricing collateral in lending protocols (conservative valuation)
    ///      - Calculating amounts when USERS RECEIVE tokens
    /// @dev INAPPROPRIATE USES:
    ///      - Pricing assets when users make payments (use ceiling division instead)
    ///      - Any scenario where protocol should receive more rather than less
    /// @dev The input and output currency are determined by the direction of the conversion in config
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
        return _getQuoteAtTick(timeWeightedAverageTick, quoteAmount, config.direction, config.roundUp);
    }

    /// @notice Validates the parameters for the Uniswap configuration during initialization or updates
    /// @param config Uniswap node configuration
    function _validateUniswapParams(UniswapNode memory config) internal pure {
        if (address(config.pool) == address(0) || config.twapPeriod == 0) {
            revert ModuleUniswapInvalidInput();
        }
    }
}
