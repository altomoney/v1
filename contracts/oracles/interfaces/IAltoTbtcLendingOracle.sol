// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode, RedstoneNode, ChainlinkRedstoneNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoTbtcLendingOracleErrors {
    /// @notice Error thrown when the input is invalid
    error AltoTbtcLendingOracleInvalidInput();

    /// @notice Error thrown when the price is invalid
    error AltoTbtcLendingOracleInvalidPrice();
}

interface IAltoTbtcLendingOracleEvents {
    /// @notice Event emitted when the chainlink and redstone node is updated
    event SetChainlinkRedstoneNode(
        ChainlinkRedstoneNode oldChainlinkRedstoneNode, ChainlinkRedstoneNode newChainlinkRedstoneNode
    );
}

interface IAltoTbtcLendingOracleBase is IOracle, IAltoTbtcLendingOracleErrors, IAltoTbtcLendingOracleEvents {
    /// @notice Gets the price of tBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the chainlink and redstone prices to get the price of BTC in USD and combines them using a weighted average
    /// @dev assumes that the invariant of tBTC pegged to BTC always holds
    /// @dev returns the chainlink price if the price from chainlink and redstone is outside the allowed deviation
    /// @return The price of tBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink and redstone node configuration
    /// @param _chainlinkRedstoneNode The new chainlink and redstone node configuration
    function updateChainlinkRedstoneNode(ChainlinkRedstoneNode memory _chainlinkRedstoneNode) external;
}

interface IAltoTbtcLendingOracle is IAltoTbtcLendingOracleBase {
    /// @notice Gets the chainlink and redstone node configuration
    /// @return The chainlink and redstone node configuration
    function chainlinkRedstoneNode() external view returns (ChainlinkRedstoneNode memory);
}

interface IAltoTbtcLendingOracleStaticTypes is IAltoTbtcLendingOracleBase {
    /// @notice Gets the chainlink and redstone node configuration
    /// @return The chainlink and redstone node configuration
    function chainlinkRedstoneNode()
        external
        view
        returns (ChainlinkNode memory, RedstoneNode memory, uint256, uint256, uint256);
}
