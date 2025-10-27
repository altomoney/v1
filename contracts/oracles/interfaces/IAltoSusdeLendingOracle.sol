// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ERC4626RatioNode, ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoSusdeLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoSusdeLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoSusdeLendingOracleInvalidPrice();
}

interface IAltoSusdeLendingOracleEvents {
    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);

    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoSusdeLendingOracleBase is IOracle, IAltoSusdeLendingOracleErrors, IAltoSusdeLendingOracleEvents {
    /// @notice The address of the SUSDE token
    function SUSDE() external view returns (address);

    /// @notice Gets the price of SUSDE in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the ERC4626 ratio to get SUSDE in USDE and uses chainlink USDE/USD price feed
    /// @return The price of SUSDE in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view returns (uint256);
    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;
    /// @notice Updates the chainlink node
    /// @param _chainlinkNode The new chainlink node
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoSusdeLendingOracle is IAltoSusdeLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);
    /// @notice Gets the chainlink node
    /// @return The chainlink node
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoSusdeLendingOracleStaticTypes is IAltoSusdeLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);
    /// @notice Gets the chainlink node
    /// @return The chainlink node
    function chainlinkNode() external view returns (AggregatorV3Interface, uint8, uint32, uint8, uint8);
}
