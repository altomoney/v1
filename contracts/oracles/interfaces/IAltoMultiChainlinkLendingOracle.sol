// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoMultiChainlinkLendingOracleEvents {
    /// @notice Event emitted when the chainlink nodes are updated
    event SetChainlinkNodes(ChainlinkNode[] oldChainlinkNodes, ChainlinkNode[] newChainlinkNodes);
}

interface IAltoMultiChainlinkLendingOracleBase is IOracle, IAltoMultiChainlinkLendingOracleEvents {
    /// @notice Gets the price of the asset in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the multiplechainlink nodes to get the price of the asset in USD
    /// @return The price of the asset in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNodes The new chainlink nodes configuration
    function updateChainlinkNodes(ChainlinkNode[] memory _chainlinkNodes) external;
}

interface IAltoMultiChainlinkLendingOracle is IAltoMultiChainlinkLendingOracleBase {
    /// @notice Gets the chainlink node at the given index
    /// @param _index The index of the chainlink node
    /// @return The chainlink node at the given index
    function chainlinkNodes(uint256 _index) external view returns (ChainlinkNode memory);
}

interface IAltoMultiChainlinkLendingOracleStaticTypes is IAltoMultiChainlinkLendingOracleBase {
    /// @notice Gets the chainlink node at the given index
    /// @param _index The index of the chainlink node
    /// @return The aggregator, conversion direction, decimals, and multiplier of the chainlink node at the given index
    function chainlinkNodes(uint256 _index)
        external
        view
        returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
}
