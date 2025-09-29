// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";

/// @title ModuleRedstone
/// @author Pearl Labs
/// @notice Module contract that is used to read from Redstone feeds
contract ModuleRedstone {
    error ModuleRedstoneInvalidRate();

    /// @notice Gets a quote for an amount of in-currency using Redstone and converts this
    /// amount to out-currency
    /// @param quoteAmount The amount for which to compute the price expressed with base decimal
    /// @param feed Redstone feed to query
    /// @param multiplied Whether the ratio outputted by Redstone should be multiplied or divided
    /// @param stalePeriod Stale period for the Redstone circuit
    /// @param inDecimals Number of decimals of the in-currency
    /// @param outDecimals Number of decimals of the out-currency
    /// @return The `quoteAmount` converted in out-currency
    function readRedstoneFeed(
        uint256 quoteAmount,
        AggregatorV3Interface feed,
        uint8 multiplied,
        uint32 stalePeriod,
        uint256 inDecimals,
        uint256 outDecimals
    ) public view returns (uint256) {
        uint256 castedRatio;
        uint8 decimals = feed.decimals();
        (uint80 roundId, int256 ratio,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        if (ratio <= 0 || roundId > answeredInRound || block.timestamp - updatedAt > stalePeriod) {
            revert ModuleRedstoneInvalidRate();
        }
        castedRatio = uint256(ratio);
        // Checking whether we should multiply or divide by the ratio computed
        // decimals of quoteAmount is the decimals of input quoteAmount
        if (multiplied == 1) {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, castedRatio, (10 ** decimals), false);
        } else {
            quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, (10 ** decimals), castedRatio, false);
        }
        // converts the quoteAmount to the out-currency decimals
        quoteAmount = FixedPointMath.divideWithRounding(quoteAmount, (10 ** outDecimals), (10 ** inDecimals), false);
        return quoteAmount;
    }
}
