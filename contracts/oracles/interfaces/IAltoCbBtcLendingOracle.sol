// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {ChainlinkNode} from "@alto/oracles/interfaces/IModuleNode.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IAltoCbBtcLendingOracleEvents {
    /// @notice Event emitted when the chainlink node is updated
    event SetChainlinkNode(ChainlinkNode oldChainlinkNode, ChainlinkNode newChainlinkNode);
}

interface IAltoCbBtcLendingOracleBase is IOracle, IAltoCbBtcLendingOracleEvents {
    /// @notice Gets the price of cbBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    /// @dev Uses the chainlink price to get the price of BTC in USD
    /// @dev assumes that the invariant of cbBTC pegged to BTC always holds
    /// @return The price of cbBTC in USD in ORACLE_PRICE_PRECISION(i.e. 1e36)
    function getPrice() external view override returns (uint256);

    /// @notice Updates the chainlink node configuration
    /// @param _chainlinkNode The new chainlink node configuration
    function updateChainlinkNode(ChainlinkNode memory _chainlinkNode) external;
}

interface IAltoCbBtcLendingOracle is IAltoCbBtcLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (ChainlinkNode memory);
}

interface IAltoCbBtcLendingOracleStaticTypes is IAltoCbBtcLendingOracleBase {
    /// @notice Gets the chainlink node configuration
    /// @return The chainlink node configuration
    function chainlinkNode() external view returns (AggregatorV3Interface, uint8, uint32, uint8, uint8);
}
