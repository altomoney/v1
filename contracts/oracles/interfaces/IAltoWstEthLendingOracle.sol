// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {ChainlinkNode, ERC4626RatioNode, ConversionDirection} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoWstEthLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoWstEthLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoWstEthLendingOracleInvalidPrice();
}

interface IAltoWstEthLendingOracleEvents {
    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);

    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);
}

interface IAltoWstEthLendingOracleBase is IOracle, IAltoWstEthLendingOracleErrors, IAltoWstEthLendingOracleEvents {
    /// @notice The address of the WSTETH token
    function WSTETH() external view returns (address);

    /// @notice Gets the price of WSTETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the ERC4626 ratio to cap the ratio of wsteth/steth
    /// @dev uses the chainlink price to get the price of ETH in USD
    /// @return The price of WSTETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the ERC4626 ratio node configuration
    /// @param _erc4626RatioNode The new ERC4626 ratio node configuration
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoWstEthLendingOracle is IAltoWstEthLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);

    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoWstEthLendingOracleStaticTypes is IAltoWstEthLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);

    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (AggregatorV3Interface, ConversionDirection, uint32, uint8, uint8);
}
