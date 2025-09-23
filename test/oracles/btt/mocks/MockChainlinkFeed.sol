// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Mock Chainlink Feed for testing purposes
contract MockChainlinkFeed is AggregatorV3Interface {
    uint8 public decimals = 8;
    string public description = "Mock Feed";
    uint256 public version = 1;

    function getRoundData(uint80)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, 100000000, block.timestamp, block.timestamp, 1); // $1000 with 8 decimals
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, 100000000, block.timestamp, block.timestamp, 1); // $1000 with 8 decimals
    }
}
