// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoCappedChainlinkOracleErrors {}

interface IAltoCappedChainlinkOracleEvents {
    /// @notice Emitted when the Chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);

    /// @notice Emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);
}

interface IAltoCappedChainlinkOracleBase is
    IOracle,
    IAltoCappedChainlinkOracleErrors,
    IAltoCappedChainlinkOracleEvents
{
    /// @notice Updates the Chainlink node
    /// @param _chainlinkNode The new Chainlink node
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;

    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;
}

/// @notice Interface with struct-typed getters (for callers that support struct returns)
interface IAltoCappedChainlinkOracle is IAltoCappedChainlinkOracleBase {
    /// @notice Returns the Chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);

    /// @notice Returns the ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);
}

/// @notice Interface with ABI-compatible static-typed getters (for callers that do not support struct returns)
interface IAltoCappedChainlinkOracleStaticTypes is IAltoCappedChainlinkOracleBase {
    /// @notice Returns the Chainlink node configuration as individual fields
    function chainlinkNode()
        external
        view
        returns (
            AggregatorV3Interface feed,
            ConversionDirection direction,
            uint32 stalePeriod,
            uint8 inDecimals,
            uint8 outDecimals,
            uint8 feedDecimals
        );

    /// @notice Returns the ERC4626 ratio node configuration as individual fields
    function erc4626RatioNode()
        external
        view
        returns (uint256 initialRatio, uint256 initialTimestamp, uint256 maxYearlyGrowthRatioWad);
}
