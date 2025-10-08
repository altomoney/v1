// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {
    ERC4626RatioNode,
    ChainlinkNode,
    RedstoneNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";

interface IAltoRethLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoRethLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoRethLendingOracleInvalidPrice();
}

interface IAltoRethLendingOracleEvents {
    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);

    /// @notice Event emitted when the chainlink and redstone node is updated
    event SetChainlinkRedstoneNode(
        ChainlinkRedstoneNode oldChainlinkRedstoneNode, ChainlinkRedstoneNode newChainlinkRedstoneNode
    );
}

interface IAltoRethLendingOracleBase is IOracle, IAltoRethLendingOracleErrors, IAltoRethLendingOracleEvents {
    /// @notice The address of the RETH token
    function RETH() external view returns (address);

    /// @notice Gets the price of RETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the ERC4626 ratio to get RETH in ETH and uses chainlink and redstone ETH/USD price feed
    /// @return The price of RETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view returns (uint256);
    /// @notice Updates the ERC4626 ratio node
    /// @param _erc4626RatioNode The new ERC4626 ratio node
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;
    /// @notice Updates the chainlink and redstone node
    /// @param _chainlinkRedstoneNode The new chainlink and redstone node
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external;
}

interface IAltoRethLendingOracle is IAltoRethLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);
    /// @notice Gets the chainlink and redstone node
    /// @return The chainlink and redstone node
    function chainlinkRedstoneNode() external view returns (ChainlinkRedstoneNode memory);
}

interface IAltoRethLendingOracleStaticTypes is IAltoRethLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node
    /// @return The ERC4626 ratio node
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);
    /// @notice Gets the chainlink and redstone node
    /// @return The chainlink and redstone node
    function chainlinkRedstoneNode()
        external
        view
        returns (ChainlinkNode memory, RedstoneNode memory, uint256, uint256, uint256);
}
