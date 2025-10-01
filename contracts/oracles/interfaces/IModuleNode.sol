// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";

/// @notice The type of oracle
enum OracleType {
    CHAINLINK,
    REDSTONE,
    UNISWAP,
    CURVE
}

/// @notice The node for the oracle
struct OracleNode {
    OracleType oracleType;
    bytes data;
}

/// @notice The node for the Chainlink oracle
struct ChainlinkNode {
    // @notice The Chainlink feed to query
    AggregatorV3Interface feed;
    // @notice Whether we should multiply or divide by this rate
    uint8 multiplied;
    // @notice The stale period for the Chainlink circuit
    uint32 stalePeriod;
    // @notice The number of decimals of the in-currency
    uint256 inDecimals;
    // @notice The number of decimals of the out-currency
    uint256 outDecimals;
}

/// @notice The node for the Redstone oracle
struct RedstoneNode {
    // @notice The Redstone feed to query
    AggregatorV3Interface feed;
    // @notice Whether we should multiply or divide by this rate
    uint8 multiplied;
    // @notice The stale period for the Redstone circuit
    uint32 stalePeriod;
    // @notice The number of decimals of the in-currency
    uint256 inDecimals;
    // @notice The number of decimals of the out-currency
    uint256 outDecimals;
}

/// @notice The node for the Uniswap oracle
struct UniswapNode {
    // @notice The Uniswap pool to query
    IUniswapV3Pool pool;
    // @notice Whether we should multiply or divide by this rate
    uint8 multiplied;
    // @notice The time weighted average period for the Uniswap pool
    uint32 twapPeriod;
}

/// @notice The node for the Curve oracle
struct CurveNode {
    // @notice The Curve pool to query
    ICurvePool pool;
    // @notice The index of the coin to query
    uint256 coinIndex;
    // @notice Whether we should multiply or divide by this rate
    uint8 multiplied;
    // @notice The number of decimals of the in-currency
    uint8 inDecimals;
    // @notice The number of decimals of the out-currency
    uint8 outDecimals;
    // @notice The minimum allowed time for the ma_exp_time of the Curve pool
    uint256 minMaExpTime;
    // @notice The stale period for the Curve pool
    uint32 stalePeriod;
}
