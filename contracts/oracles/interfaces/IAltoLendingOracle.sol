// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";

enum OracleType {
    CHAINLINK,
    REDSTONE,
    UNISWAP,
    CURVE
}

struct OracleNode {
    OracleType oracleType;
    bytes data;
}

struct ChainlinkNode {
    AggregatorV3Interface feed;
    uint8 multiplied;
    uint32 stalePeriod;
    uint256 inDecimals;
    uint256 outDecimals;
}

struct RedstoneNode {
    AggregatorV3Interface feed;
    uint8 multiplied;
    uint32 stalePeriod;
    uint256 inDecimals;
    uint256 outDecimals;
}

struct UniswapNode {
    IUniswapV3Pool pool;
    uint8 multiplied;
    uint32 twapPeriod;
}

struct CurveNode {
    ICurvePool pool;
    uint256 coinIndex;
    uint8 multiplied;
    uint8 inDecimals;
    uint8 outDecimals;
    uint256 minMaExpTime;
    uint32 stalePeriod;
}

interface IAltoWethLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoWethLendingOracleInvalidInput();
}
