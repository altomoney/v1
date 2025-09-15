// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

uint256 constant USD_ORACLE_PRICE_PRECISION = 1e8;

interface IUsdOracleErrors {
    error InvalidInput();
}

interface IUsdOracle is IUsdOracleErrors {
    /// @notice Gets the price of the asset in USD_ORACLE_PRICE_PRECISION
    /// @return The price of the asset in USD_ORACLE_PRICE_PRECISION
    function getPrice() external view returns (uint256);
}
