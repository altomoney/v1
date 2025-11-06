// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoWbtcLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoWbtcLendingOracleInvalidInput();
}

interface IAltoWbtcLendingOracleEvents {
    /// @notice Event emitted when the chainlink node 1 is updated
    event SetChainlinkNode1(ChainlinkNode oldChainlinkNode1, ChainlinkNode newChainlinkNode1);

    /// @notice Event emitted when the chainlink node 2 is updated
    event SetChainlinkNode2(ChainlinkNode oldChainlinkNode2, ChainlinkNode newChainlinkNode2);
}

interface IAltoWbtcLendingOracleBase is IOracle, IAltoWbtcLendingOracleErrors, IAltoWbtcLendingOracleEvents {
    /// @notice Gets the price of WBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the chainlink price to get the ratio of WBTC to BTC and the price of BTC in USD
    /// @return The price of WBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink node configuration
    /// @param _index The index of the chainlink node to update
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(uint256 _index, ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoWbtcLendingOracle is IAltoWbtcLendingOracleBase {
    /// @notice Gets the chainlink node 1 configuration
    /// @return The chainlink node configuration
    function chainlinkNode1() external view returns (ChainlinkNode memory);

    /// @notice Gets the chainlink node 2 configuration
    /// @return The chainlink node 2 configuration
    function chainlinkNode2() external view returns (ChainlinkNode memory);
}

interface IAltoWbtcLendingOracleStaticTypes is IAltoWbtcLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode1() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);

    /// @notice Gets the chainlink node 2 configuration
    /// @return The chainlink node 2 configuration
    function chainlinkNode2() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
}
