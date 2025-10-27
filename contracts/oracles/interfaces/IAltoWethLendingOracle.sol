// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoWethLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoWethLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoWethLendingOracleInvalidPrice();
}

interface IAltoWethLendingOracleEvents {
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoWethLendingOracleBase is IOracle, IAltoWethLendingOracleErrors, IAltoWethLendingOracleEvents {
    /// @notice Gets the price of WETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the chainlink price to get the price of ETH in USD
    /// @return The price of WETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoWethLendingOracle is IAltoWethLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoWethLendingOracleStaticTypes is IAltoWethLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (AggregatorV3Interface, uint8, uint32, uint8, uint8);
}
