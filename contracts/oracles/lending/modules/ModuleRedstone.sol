// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {RedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";

/// @title ModuleRedstone
/// @author Pearl Labs
/// @notice Module contract that is used to read from Redstone feeds
contract ModuleRedstone {
    error ModuleRedstoneInvalidRate();
    error ModuleRedstoneInvalidInput();

    /// @notice Gets a quote for an amount of in-currency using Redstone and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount for which to compute the price expressed with base decimal
    /// @param config Redstone node configuration
    /// @return The `quoteAmount` converted in out-currency in out decimals
    function readRedstoneFeed(uint256 quoteAmount, RedstoneNode memory config) public view returns (uint256) {
        uint256 castedRatio;
        uint8 decimals = config.feed.decimals();
        (uint80 roundId, int256 ratio,, uint256 updatedAt, uint80 answeredInRound) = config.feed.latestRoundData();
        if (ratio <= 0 || roundId > answeredInRound || block.timestamp - updatedAt > config.stalePeriod) {
            revert ModuleRedstoneInvalidRate();
        }
        castedRatio = uint256(ratio);
        // Checking whether we should multiply or divide by the ratio computed
        // decimals of quoteAmount is the decimals of input quoteAmount
        if (config.multiplied == 1) {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, castedRatio, (10 ** decimals), false);
        } else {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, (10 ** decimals), castedRatio, false);
        }
        // converts the quoteAmount to the out-currency decimals
        quoteAmount =
            FixedPointMath.divideWithRounding(quoteAmount, (10 ** config.outDecimals), (10 ** config.inDecimals), false);
        return quoteAmount;
    }

    /// @notice Validates the parameters for the Redstone feed during initialization or updates
    /// @param config Redstone node configuration
    function _validateRedstoneParams(RedstoneNode memory config) internal pure {
        if (
            address(config.feed) == address(0) || config.stalePeriod == 0 || config.inDecimals == 0
                || config.outDecimals == 0
        ) {
            revert ModuleRedstoneInvalidInput();
        }

        if (config.multiplied != 0 && config.multiplied != 1) {
            revert ModuleRedstoneInvalidInput();
        }
    }
}
