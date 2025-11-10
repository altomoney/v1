// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

uint256 constant USD_ORACLE_PRICE_PRECISION = 1e8;

/// @title IUsdOracle
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice This represents the oracle that returns the price of the asset in USD
/// @dev This is supposed to return the price of the asset in with USD_ORACLE_PRICE_PRECISION precision
interface IUsdOracle {
    /// @notice Returns the price of the asset in USD
    /// @return The price of the asset in USD in USD_ORACLE_PRICE_PRECISION precision
    function getPrice() external view returns (uint256);
}
