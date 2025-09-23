// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUsdOracle} from "@alto/oracles/interfaces/IUsdOracle.sol";

interface IRewardsOracle is IUsdOracle {
    error InvalidInput();
    error NotInitiated();
    error TooEarlyToUpdatePrice();
    error AlreadyStartedTwapPeriod();

    /// @notice Parameters for initializing the RewardsOracle
    struct RewardsOracleInitParams {
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
        /// @dev The initial price of the asset
        uint256 initialPrice;
        /// @dev Description of the assets concerned by the oracle
        bytes32 description;
    }

    /// @notice Emitted when the price is updated
    /// @param timestamp The timestamp when the price was updated
    /// @param newPrice The new price
    /// @param oldPrice The old price
    event PriceUpdated(uint256 indexed timestamp, uint256 newPrice, uint256 oldPrice);
}
