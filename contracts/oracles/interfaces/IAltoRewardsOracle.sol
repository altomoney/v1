// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUsdOracle} from "@alto/oracles/interfaces/IUsdOracle.sol";

/// @notice Parameters for initializing the AltoRewardsOracle
struct AltoRewardsOracleInitParams {
    /// @dev List of 2 addresses representing the in-currency address and the out-currency address
    address[] addressInAndOutUni;
    /// @dev Path of the Uniswap pools
    IUniswapV3Pool[] circuitUniswap;
    /// @dev Whether we should multiply or divide by this rate in the path
    uint8[] circuitUniIsMultiplied;
    /// @dev Time weighted average window for all Uniswap pools
    uint32 twapPeriod;
    /// @dev Number of observations that each pool should have stored
    uint16 observationLength;
    /// @dev Whether we need to use the last Chainlink oracle to convert to another
    /// currency / asset (Forex for instance)
    uint8 uniFinalCurrency;
    /// @dev Chainlink pool addresses put in order
    address[] circuitChainlink;
    /// @dev Whether we should multiply or divide by this rate
    uint8[] circuitChainIsMultiplied;
    /// @dev The initial owner of the contract.
    address owner;
    /// @dev The stale period for the Chainlink oracle
    uint32 stalePeriod;
    /// @dev Description of the assets concerned by the oracle
    bytes32 description;
    /// @dev Minimum time interval (in seconds) required between price updates
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
    /// @param newPrice The new price
    /// @param oldPrice The old price
    event PriceUpdated(uint256 indexed timestamp, uint256 newPrice, uint256 oldPrice);

    /// @notice Emitted when the price update cooldown period is updated
    /// @param oldPriceUpdateCooldownPeriod The old price update cooldown period
    /// @param newPriceUpdateCooldownPeriod The new price update cooldown period
    event PriceUpdateCooldownPeriodUpdated(uint256 oldPriceUpdateCooldownPeriod, uint256 newPriceUpdateCooldownPeriod);
}

interface IAltoRewardsOracle is IUsdOracle, IAltoRewardsOracleErrors, IAltoRewardsOracleEvents {
    /// @notice Unit of the in-currency
    function IN_BASE() external view returns (uint256);

    /// @notice Unit out Uniswap currency
    function OUT_BASE() external view returns (uint256);

    /// @notice Whether the final rate obtained with Uniswap should be multiplied to last rate from Chainlink
    function UNI_FINAL_CURRENCY() external view returns (uint8);

    /// @notice Timestamp when this oracle was last updated to return the new price
    function lastPriceUpdateTimestamp() external view returns (uint256);

    /// @notice Minimum time interval (in seconds) required between price updates
    function priceUpdateCooldownPeriod() external view returns (uint256);

    /// @notice Cached price of the asset to be returned by getPrice function
    function cachedPrice() external view returns (uint256);

    /// @notice Description of the oracle
    function description() external view returns (bytes32);

    /// @notice Gets the price of the asset in USD_ORACLE_PRICE_PRECISION
    /// @return The price of the asset in USD_ORACLE_PRICE_PRECISION
    function getPrice() external view override returns (uint256);

    /// @notice Starts the TWAP period
    /// @dev This function will be called after Uniswap pool has been created
    /// @dev getPrice function will return the cached price until the price is updated through updatePrice function
    function startTwapPeriod(uint256 _initialPrice) external;

    /// @notice Updates the price of the asset based on the Uniswap V3 twap period
    /// @dev This function will be called periodically to update the price of the asset
    /// @dev This function will revert if the twap period has not been passed since the last update
    function updatePrice() external;

    /// @notice Updates the price update cooldown period
    /// @param _priceUpdateCooldownPeriod The new price update cooldown period
    function updatePriceUpdateCooldownPeriod(uint256 _priceUpdateCooldownPeriod) external;
}
