// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {UniswapNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IUsdOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Parameters for initializing the AltoRewardsOracle
struct AltoRewardsOracleInitParams {
    // @notice The Uniswap node to query
    UniswapNode uniswapNode;
    // @notice The Chainlink node to query
    ChainlinkNode chainlinkNode;
    // @notice The initial owner of the contract.
    address owner;
    // @notice Minimum time interval (in seconds) required between price updates
    uint256 priceUpdateCooldownPeriod;
}

interface IAltoRewardsOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoRewardsOracleInvalidInput();
    /// @notice Error thrown when the oracle is not initiated
    error AltoRewardsOracleNotInitiated();
    /// @notice Error thrown when the price is updated too early
    error AltoRewardsOracleTooEarlyToUpdatePrice();
    /// @notice Error thrown when the twap period has already been started
    error AltoRewardsOracleAlreadyStartedTwapPeriod();
}

interface IAltoRewardsOracleEvents {
    /// @notice Emitted when the price is updated
    /// @param timestamp The timestamp when the price was updated
    /// @param oldPrice The old price
    /// @param newPrice The new price
    event PriceUpdated(uint256 indexed timestamp, uint256 oldPrice, uint256 newPrice);

    /// @notice Emitted when the price update cooldown period is updated
    /// @param oldPriceUpdateCooldownPeriod The old price update cooldown period
    /// @param newPriceUpdateCooldownPeriod The new price update cooldown period
    event PriceUpdateCooldownPeriodUpdated(uint256 oldPriceUpdateCooldownPeriod, uint256 newPriceUpdateCooldownPeriod);

    /// @notice Emitted when the Uniswap node is updated
    /// @param oldUniswapNode The old Uniswap node
    /// @param newUniswapNode The new Uniswap node
    event SetUniswapNode(UniswapNode oldUniswapNode, UniswapNode newUniswapNode);

    /// @notice Emitted when the Chainlink node is updated
    /// @param oldChainlinkNode The old Chainlink node
    /// @param newChainlinkNode The new Chainlink node
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoRewardsOracleBase is IUsdOracle, IAltoRewardsOracleErrors, IAltoRewardsOracleEvents {
    /// @notice 1 full unit of the in-currency with decimals
    function inTokenOneUnit() external view returns (uint256);

    /// @notice Timestamp when this oracle was last updated to return the new price
    function lastPriceUpdateTimestamp() external view returns (uint256);

    /// @notice Minimum time interval (in seconds) required between price updates
    function priceUpdateCooldownPeriod() external view returns (uint256);

    /// @notice Cached price of the asset to be returned by getPrice function
    function cachedPrice() external view returns (uint256);

    /// @notice Starts the TWAP period
    /// @dev This function has to be called after deployment to initiate cooldown mechanism
    /// @param _initialPrice The initial price to be returned by getPrice function before first `priceUpdateCooldownPeriod` passes
    /// @dev getPrice function will return the `_initialPrice` until the price is updated through updatePrice function
    function startTwapPeriod(uint256 _initialPrice) external;

    /// @notice Updates the price of the asset based on the Uniswap V3 twap period
    /// @dev This function will be called periodically to update the price of the asset
    /// @dev This function will revert if the `priceUpdateCooldownPeriod` did not pass since the last update
    function updatePrice() external;

    /// @notice Updates the price update cooldown period
    /// @param _priceUpdateCooldownPeriod The new price update cooldown period
    function updatePriceUpdateCooldownPeriod(uint256 _priceUpdateCooldownPeriod) external;

    /// @notice Updates the Uniswap node
    /// @param _uniswapNode The new Uniswap node
    function updateUniswapNode(UniswapNode memory _uniswapNode) external;

    /// @notice Updates the Chainlink node
    /// @param _chainlinkNode The new Chainlink node
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoRewardsOracle is IAltoRewardsOracleBase {
    /// @notice Gets the Uniswap node
    /// @return The Uniswap node
    function uniswapNode() external view returns (UniswapNode memory);

    /// @notice Gets the Chainlink node
    /// @return The Chainlink node
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoRewardsOracleStaticTypes is IAltoRewardsOracleBase {
    /// @notice Gets the Uniswap node
    /// @return The Uniswap node
    function uniswapNode() external view returns (IUniswapV3Pool, ConversionDirection, uint32);

    /// @notice Gets the Chainlink node
    /// @return The Chainlink node
    function chainlinkNode() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
}
