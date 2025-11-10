// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoTbtcLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoTbtcLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoTbtcLendingOracleInvalidPrice();
}

interface IAltoTbtcLendingOracleEvents {
    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoTbtcLendingOracleBase is IOracle, IAltoTbtcLendingOracleErrors, IAltoTbtcLendingOracleEvents {
    /// @notice Gets the price of tBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the chainlink price to get the price of BTC in USD
    /// @dev assumes that the invariant of tBTC pegged to BTC always holds
    /// @return The price of tBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoTbtcLendingOracle is IAltoTbtcLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoTbtcLendingOracleStaticTypes is IAltoTbtcLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
}
