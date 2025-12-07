// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoMultiChainlinkLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoMultiChainlinkLendingOracleInvalidInput();
}

interface IAltoMultiChainlinkLendingOracleEvents {
    /// @notice Event emitted when the chainlink nodes are updated
    event SetChainlinkNodes(ChainlinkNode[] oldChainlinkNodes, ChainlinkNode[] newChainlinkNodes);
}

interface IAltoMultiChainlinkLendingOracleBase is
    IOracle,
    IAltoMultiChainlinkLendingOracleErrors,
    IAltoMultiChainlinkLendingOracleEvents
{
    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNodes The new chainlink nodes configuration
    function updateChainlinkNodes(ChainlinkNode[] memory _chainlinkNodes) external;
}

interface IAltoMultiChainlinkLendingOracle is IAltoMultiChainlinkLendingOracleBase {
    /// @notice Gets the chainlink node at the given index
    /// @param _index The index of the chainlink node
    /// @return The chainlink node at the given index
    /// @dev Read ChainlinkNode documentation for more details on the struct before using this contract
    function chainlinkNodes(uint256 _index) external view returns (ChainlinkNode memory);
}

interface IAltoMultiChainlinkLendingOracleStaticTypes is IAltoMultiChainlinkLendingOracleBase {
    /// @notice Gets the chainlink node at the given index
    /// @param _index The index of the chainlink node
    /// @return The chainlink node at the given index
    /// @dev Read ChainlinkNode documentation for more details on the struct before using this contract
    function chainlinkNodes(uint256 _index)
        external
        view
        returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8, uint8);
}
