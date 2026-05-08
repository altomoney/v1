// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ICurveStableSwapNGOracle} from "@alto/interfaces/curve/ICurveStableSwapNG.sol";

/// @notice The direction of the conversion
/// @dev See individual node structs for more details
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
    // For example: if the chainlink feed is ETH/USD and we want to input ETH and output USD, we should set direction to IN_TO_OUT
    // if the chainlink feed is USD/ETH and we want to input USD and output ETH, we should set direction to OUT_TO_IN
    ConversionDirection direction;
    // @notice The stale period for the Chainlink circuit in seconds
    // @dev This is the maximum time that the price can be stale
    uint32 stalePeriod;
    // @notice The number of decimals of the in-currency
    // @dev This is the decimals of the in-currency of the feed
    // For example: for ETH/USD feed, inDecimals should be 18 (ETH decimals)
    uint8 inDecimals;
    // @notice The number of decimals of the out-currency
    // @dev This is the decimals of the currency that we want to conver the final result to
    // @dev THIS IS NOT the decimals of the out-currency of the feed (that decimals are fetched from the feed dynamically)
    // For example: ETH/USD feed has 8 decimals, but we want to convert the final result to
    // LENDING_ORACLE_PRICE_PRECISION decimals, so outDecimals should be 36 and inDecimals should be 18 (ETH decimals)
    uint8 outDecimals;
    // @notice The number of decimals of the feed
    uint8 feedDecimals;
}

/// @notice The node for the Uniswap oracle
struct UniswapNode {
    // @notice The Uniswap V3 pool to query the price from
    IUniswapV3Pool pool;
    // @notice Specifies the direction of the conversion
    // IN_TO_OUT: token0 to token1 where we multiply quoted amount by the ratio
    // OUT_TO_IN: token1 to token0 where we divide quoted amount by the ratio
    // For example: if the Uniswap pool is WETH/USDC and we want to input WETH and output USDC, we should set direction to IN_TO_OUT
    // if the Uniswap pool is USDC/WETH and we want to input USDC and output WETH, we should set direction to OUT_TO_IN
    ConversionDirection direction;
    // @notice The time weighted average period for the Uniswap pool
    // @dev This is the period over which the price is calculated
    // @dev IT IS ABSOLUTELY NECESSARY to verify that pools cardinality is big enough to support specified TWAP period
    // see the `observationCardinalityNext` function in the Uniswap V3 pool contract for more details
    uint32 twapPeriod;
    // @notice Whether to round up the price to the nearest integer
    // @dev roundUp should be true when rounding needs to be done in favor of protocol(or against the user) and vice versa
    // @dev roundUp should be true when:
    //      - Pricing collateral in lending protocols (conservative valuation)
    //      - Calculating amounts when USERS RECEIVE tokens
    // @dev roundUp should be false when:
    //      - Pricing assets when users make payments
    //      - Any scenario where protocol should receive more rather than less
    bool roundUp;
}

/// @notice The node for the Curve oracle
struct CurveNode {
    // @notice The Curve pool to query
    ICurveStableSwapNGOracle pool;
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

/// @notice The node for the ERC4626 ratio oracle
struct ERC4626RatioNode {
    // @notice The initial ratio of the ERC4626 vault
    uint256 initialRatio;
    // @notice The initial timestamp of the ERC4626 vault when the initial ratio was queried
    uint256 initialTimestamp;
    // @notice The maximum yearly growth ratio of the ERC4626 vault defined in MATH_PRECISION (i.e. MATH_PRECISION = 100%)
    // @dev This is the maximum allowed growth rate of the ratio of the ERC4626 vault in one year
    // @dev This is used to prevent the ratio from growing too fast
    uint256 maxYearlyGrowthRatioWad;
}

// @dev The module using this node should multiply the input by the multiplier
struct MultiplierNode {
    // @notice The multiplier to apply to the input
    uint256 multiplier;
}

/// @notice The node for the Linear Discount oracle
/// @dev This would be used for PT tokens where we apply linear discount to the price of PT tokens based om time to maturity
struct LinearDiscountNode {
    // @notice The PT token address
    address ptToken;
    // @notice The maturity timestamp of the PT token
    // @dev Must be in the future at configuration time
    uint256 maturity;
    // @notice The base discount rate per year expressed in WAD (1e18 = 100%)
    // @dev Maximum allowed value is 1e18 (100%)
    uint256 baseDiscountPerYear;
    // @notice The number of decimals of the in-currency (quoteAmount)
    uint8 inDecimals;
    // @notice The number of decimals of the out-currency
    uint8 outDecimals;
}
