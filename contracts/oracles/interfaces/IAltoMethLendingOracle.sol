// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {ChainlinkNode, ERC4626RatioNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoMethLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoMethLendingOracleInvalidInput();
}

interface IAltoMethLendingOracleEvents {
    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);

    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);
}

interface IAltoMethLendingOracleBase is IOracle, IAltoMethLendingOracleErrors, IAltoMethLendingOracleEvents {
    /// @notice The address of the mETH Staking contract
    function METH_STAKING() external view returns (address);

    /// @notice Gets the price of mETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the ERC4626 ratio to cap the ratio of mETH to ETH
    /// @dev uses the chainlink price to get the price of ETH in USD
    /// @return The price of mETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the ERC4626 ratio node configuration
    /// @param _erc4626RatioNode The new ERC4626 ratio node configuration
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoMethLendingOracle is IAltoMethLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);

    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoMethLendingOracleStaticTypes is IAltoMethLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);

    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (AggregatorV3Interface, uint8, uint32, uint8, uint8);
}
