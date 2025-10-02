// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {
    ChainlinkNode,
    RedstoneNode,
    ERC4626RatioNode,
    ChainlinkRedstoneNode
} from "@alto/oracles/interfaces/IModuleNode.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoWstEthLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoWstEthLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoWstEthLendingOracleInvalidPrice();
}

interface IAltoWstEthLendingOracleEvents {
    /// @notice Event emitted when the maximum allowed deviation is updated
    event SetMaxAllowedDeviation(uint256 oldMaxAllowedDeviation, uint256 newMaxAllowedDeviation);

    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkRedstoneNode(
        ChainlinkRedstoneNode oldChainlinkRedstoneNode, ChainlinkRedstoneNode newChainlinkRedstoneNode
    );

    /// @notice Event emitted when the redstone node is updated
    event SetRedstoneNode(RedstoneNode oldRedstoneNode, RedstoneNode newRedstoneNode);

    /// @notice Event emitted when the ERC4626 ratio node is updated
    event SetERC4626RatioNode(ERC4626RatioNode oldERC4626RatioNode, ERC4626RatioNode newERC4626RatioNode);
}

interface IAltoWstEthLendingOracleBase is IOracle, IAltoWstEthLendingOracleErrors, IAltoWstEthLendingOracleEvents {
    /// @notice The address of the WSTETH token
    function WSTETH() external view returns (address);

    /// @notice The maximum allowed deviation between the chainlink and redstone prices
    function maxAllowedDeviation() external view returns (uint256);

    /// @notice Gets the price of WSTETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the ERC4626 ratio to cap the ratio of wsteth/steth
    /// @dev uses the chainlink and redstone prices to get the price of ETH in USD and combines them using a weighted average
    /// @dev also checks the max allowed deviation with redstone WSTETH/USD feed
    /// @return The price of WSTETH in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the ERC4626 ratio node configuration
    /// @param _erc4626RatioNode The new ERC4626 ratio node configuration
    function updateERC4626RatioNode(ERC4626RatioNode memory _erc4626RatioNode) external;

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkRedstoneNode The new chainlink redstone node configuration
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external;

    /// @notice Updates the redstone node configuration
    /// @param _redstoneNode The new redstone node configuration
    function updateRedstoneNode(RedstoneNode memory _redstoneNode) external;

    /// @notice Updates the maximum allowed deviation between the chainlink and redstone prices
    /// @param _maxAllowedDeviation The new maximum allowed deviation between the chainlink and redstone prices
    function updateMaxAllowedDeviation(uint256 _maxAllowedDeviation) external;
}

interface IAltoWstEthLendingOracle is IAltoWstEthLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (ERC4626RatioNode memory);

    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkRedstoneNode() external view returns (ChainlinkRedstoneNode memory);

    /// @notice Gets the redstone node configuration
    /// @return The redstone node configuration
    function redstoneNode() external view returns (RedstoneNode memory);
}

interface IAltoWstEthLendingOracleStaticTypes is IAltoWstEthLendingOracleBase {
    /// @notice Gets the ERC4626 ratio node configuration
    /// @return The ERC4626 ratio node configuration
    function erc4626RatioNode() external view returns (uint256, uint256, uint256);

    /// @notice Gets the chainlink and redstone node configuration
    /// @return The chainlink and redstone node configuration
    function chainlinkRedstoneNode()
        external
        view
        returns (ChainlinkNode memory, RedstoneNode memory, uint256, uint256, uint256);

    /// @notice Gets the redstone node configuration
    /// @return The redstone node configuration
    function redstoneNode() external view returns (AggregatorV3Interface, uint8, uint32, uint8, uint8);
}
