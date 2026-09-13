// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

/// @title Alto Credit Market LP Oracle
/// @notice Values the credit market LP collateral at a fixed one-to-one price in DUSD.
contract AltoCreditMarketLpOracle is IOracle {
    /// @inheritdoc IOracle
    function getPrice() external pure returns (uint256) {
        return LENDING_ORACLE_PRICE_PRECISION;
    }
}
