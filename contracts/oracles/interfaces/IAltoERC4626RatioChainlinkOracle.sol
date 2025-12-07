// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC4626RatioNode, ChainlinkNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoERC4626RatioChainlinkOracleErrors {}

interface IAltoERC4626RatioChainlinkOracleEvents {
    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);

    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoERC4626RatioChainlinkOracleBase is
    IOracle,
    IAltoERC4626RatioChainlinkOracleErrors,
    IAltoERC4626RatioChainlinkOracleEvents
{
    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;
    /// @notice Updates the chainlink node
    /// @param _chainlinkNode The new chainlink node
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoERC4626RatioChainlinkOracle is IAltoERC4626RatioChainlinkOracleBase {
    /// @notice Gets the ERC4626RatioNode
    /// @return The ERC4626RatioNode
    /// @dev Read ERC4626RatioNode documentation for more details on the struct before using this contract
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);
    /// @notice Gets the ChainlinkNode
    /// @return The ChainlinkNode
    /// @dev Read ChainlinkNode documentation for more details on the struct before using this contract
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoERC4626RatioChainlinkOracleStaticTypes is IAltoERC4626RatioChainlinkOracleBase {
    /// @notice Gets the ERC4626RatioNode
    /// @return The ERC4626RatioNode
    /// @dev Read ERC4626RatioNode documentation for more details on the struct before using this contract
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);
    /// @notice Gets the ChainlinkNode
    /// @return The ChainlinkNode
    /// @dev Read ChainlinkNode documentation for more details on the struct before using this contract
    function chainlinkNode()
        external
        view
        returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8, uint8);
}
