// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleChainlink
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice Utility contract used to read from Chainlink price feeds
contract ModuleChainlink {
    error ModuleChainlinkInvalidRate();
    error ModuleChainlinkInvalidInput();

    /// @notice Gets a quote for an amount of input currency and returns the output currency
    /// @param quoteAmount The input currency amount to get the price of in output currency
    /// @param config Chainlink configuration
    /// @dev The input and output currency are determined by the direction of the conversion in config
    /// @return The value of the `quoteAmount` in output currency
    /// @dev This will revert if the price is stale, if the ratio is invalid, or if there's a round id mismatch
    function readChainlinkFeed(uint256 quoteAmount, ChainlinkNode memory config) public view returns (uint256) {
        (uint80 roundId, int256 ratio,, uint256 updatedAt, uint80 answeredInRound) = config.feed.latestRoundData();
        if (ratio <= 0 || roundId > answeredInRound || block.timestamp - updatedAt > config.stalePeriod) {
            revert ModuleChainlinkInvalidRate();
        }

        // Storing these to improve readability
        uint256 price = uint256(ratio);
        uint256 powFeed = 10 ** config.feed.decimals();
        uint256 powIn = 10 ** config.inDecimals;
        uint256 powOut = 10 ** config.outDecimals;

        // Checking whether we should multiply or divide by the ratio
        // Combine price application and decimals conversion to minimize rounding loss
        if (config.direction == ConversionDirection.IN_TO_OUT) {
            // quoteAmount = quoteAmount * ratio / 10^feedDecimals * 10^outDecimals / 10^inDecimals
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, price * powOut, powFeed * powIn, false);
        } else {
            // quoteAmount = quoteAmount * 10^feedDecimals / ratio * 10^outDecimals / 10^inDecimals
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, powFeed * powOut, price * powIn, false);
        }

        return quoteAmount;
    }

    /// @notice Validates the parameters for the Chainlink feed during initialization or updates
    /// @param config Chainlink node configuration
    function _validateChainlinkParams(ChainlinkNode memory config) internal pure {
        if (address(config.feed) == address(0) || config.stalePeriod == 0) {
            revert ModuleChainlinkInvalidInput();
        }

        // Bound decimals to prevent overflow and DoS via extreme values
        // 54 is LENDING_ORACLE_PRICE_PRECISION + 18 decimal input token - everything above this is
        // unrealistic and potentially dangerous (this is considered a sanity check)
        if (config.inDecimals + config.outDecimals > 54) {
            revert ModuleChainlinkInvalidInput();
        }
    }
}
