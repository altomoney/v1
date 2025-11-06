// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {CurveNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {ICurvePool} from "@alto/oracles/interfaces/ICurvePool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoPxEthLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoPxEthLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoPxEthLendingOracleInvalidPrice();

    /// @notice Error thrown when the liquidity is insufficient
    error AltoPxEthLendingOracleInsufficientLiquidity();
}

interface IAltoPxEthLendingOracleEvents {
    /// @notice Emitted when the minimum allowed liquidity pool for curve pool 1 is updated
    event SetMinAllowedLiquidityPool1(uint256[] oldMinAllowedLiquidityPool1, uint256[] newMinAllowedLiquidityPool1);

    /// @notice Emitted when the minimum allowed liquidity pool for curve pool 2 is updated
    event SetMinAllowedLiquidityPool2(uint256[] oldMinAllowedLiquidityPool2, uint256[] newMinAllowedLiquidityPool2);

    /// @notice Emitted when the curve node for curve pool 1 is updated
    event SetCurveNode1(CurveNode oldCurveNode1, CurveNode newCurveNode1);

    /// @notice Emitted when the curve node for curve pool 2 is updated
    event SetCurveNode2(CurveNode oldCurveNode2, CurveNode newCurveNode2);

    /// @notice Emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);

    /// @notice Emitted when the maximum allowed deviation is updated
    event SetMaxAllowedDeviation(uint256 oldMaxAllowedDeviation, uint256 newMaxAllowedDeviation);
}

interface IAltoPxEthLendingOracleBase is IOracle, IAltoPxEthLendingOracleErrors, IAltoPxEthLendingOracleEvents {
    /// @notice The maximum allowed deviation in WAD(1e18 = 100%)
    /// @return The maximum allowed deviation in WAD(1e18 = 100%)
    function maxAllowedDeviation() external view returns (uint256);
    /// @notice Gets the price of PXETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the curve and chainlink prices to get the price of PXETH in USD
    /// @dev averages the price of PXETH/WETH and PXETH/STETH curve pool
    /// @dev uses chainlink to get the price of ETH in USD
    /// @return The price of PXETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view returns (uint256);
    /// @notice Updates the curve node for curve pool 1
    /// @param _isNode1 Whether the curve node is for curve pool 1
    /// @param _curveNode1 The new curve node for curve pool 1
    /// @param _isNode2 Whether the curve node is for curve pool 2
    /// @param _curveNode2 The new curve node for curve pool 2
    function updateCurveNode(bool _isNode1, CurveNode memory _curveNode1, bool _isNode2, CurveNode memory _curveNode2)
        external;
    /// @notice Updates the minimum allowed liquidity pool for curve pool 1
    /// @param _isForPool1 Whether the minimum allowed liquidity pool is for curve pool 1
    /// @param _minAllowedLiquidityPool The new minimum allowed liquidity pool
    function updateMinAllowedLiquidityPoo1(bool _isForPool1, uint256[] memory _minAllowedLiquidityPool) external;
    /// @notice Updates the chainlink node
    /// @param _chainlinkNode The new chainlink node
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
    /// @notice Updates the maximum allowed deviation
    /// @param _maxAllowedDeviation The new maximum allowed deviation
    function updateMaxAllowedDeviation(uint256 _maxAllowedDeviation) external;
}

interface IAltoPxEthLendingOracle is IAltoPxEthLendingOracleBase {
    /// @notice Gets the curve node for curve pool 1
    /// @return The curve node for curve pool 1
    function curveNode1() external view returns (CurveNode memory);
    /// @notice Gets the curve node for curve pool 2
    /// @return The curve node for curve pool 2
    function curveNode2() external view returns (CurveNode memory);
    /// @notice Gets the chainlink node
    /// @return The chainlink node
    function chainlinkNode() external view returns (ChainlinkNode memory);
    /// @notice Gets the minimum allowed liquidity pool for curve pool 1
    /// @return The minimum allowed liquidity pool for curve pool 1
    function minAllowedLiquidityPool1() external view returns (uint256[] memory);
    /// @notice Gets the minimum allowed liquidity pool for curve pool 2
    /// @return The minimum allowed liquidity pool for curve pool 2
    function minAllowedLiquidityPool2() external view returns (uint256[] memory);
}

interface IAltoPxEthLendingOracleStaticTypes is IAltoPxEthLendingOracleBase {
    /// @notice Gets the curve node for curve pool 1
    /// @return The curve node for curve pool 1
    function curveNode1() external view returns (ICurvePool, uint256, uint8, uint8, uint8, uint256, uint32);
    /// @notice Gets the curve node for curve pool 2
    /// @return The curve node for curve pool 2
    function curveNode2() external view returns (ICurvePool, uint256, uint8, uint8, uint8, uint256, uint32);
    /// @notice Gets the chainlink node
    /// @return The chainlink node
    function chainlinkNode() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
    /// @notice Gets the minimum allowed liquidity pool for curve pool 1 for asset at index
    /// @return The minimum allowed liquidity pool for curve pool 1 for asset at index
    function minAllowedLiquidityPool1(uint256 index) external view returns (uint256);
    /// @notice Gets the minimum allowed liquidity pool for curve pool 2 for asset at index
    /// @return The minimum allowed liquidity pool for curve pool 2 for asset at index
    function minAllowedLiquidityPool2(uint256 index) external view returns (uint256);
}
