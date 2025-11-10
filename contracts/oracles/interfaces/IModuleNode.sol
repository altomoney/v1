// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";

enum ConversionDirection {
    IN_TO_OUT,
    OUT_TO_IN
}

/// @notice The node for the Chainlink oracle
struct ChainlinkNode {
    // @notice The Chainlink feed to query
    AggregatorV3Interface feed;
    // @notice Specifies the direction of the conversion
    // IN_TO_OUT: in-currency to out-currency where we multiply quoted amount by the ratio
    // OUT_TO_IN: out-currency to in-currency where we divide quoted amount by the ratio
    ConversionDirection direction;
    // @notice The stale period for the Chainlink circuit
    uint32 stalePeriod;
    // @notice The number of decimals of the in-currency
    // @dev this is the decimals of the in-currency of the feed
    uint8 inDecimals;
    // @notice The number of decimals of the out-currency
    // @dev this is the decimals of the currency that we want to conver the final result to
    // THIS IS NOT the decimals of the out-currency of the feed
    // for example: ETH/USD feed has 8 decimals, but we want to convert the final result to
    // ORACLE_PRICE_PRECISION decimals, so outDecimals should be 36 and inDecimals should be 18 (ETH decimals)
    uint8 outDecimals;
}

/// @notice The node for the Uniswap oracle
struct UniswapNode {
    // @notice The Uniswap pool to query
    IUniswapV3Pool pool;
    // @notice Whether we should multiply or divide by this rate
    ConversionDirection direction;
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

/// @notice The node for the ERC4626 ratio
struct ERC4626RatioNode {
    // @notice The initial ratio of the ERC4626 vault
    uint256 initialRatio;
    // @notice The initial timestamp of the ERC4626 vault when the initial ratio was set
    uint256 initialTimestamp;
    // @notice The maximum yearly growth ratio of the ERC4626 vault defined in wad. (1e18 = 100%)
    uint256 maxYearlyGrowthRatioWad;
}
