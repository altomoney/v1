// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title IOracle
/// @notice This represents basic oracle interface
interface IOracle {
    /// @notice Returns the price of the asset
    /// @return The price of the asset
    function getPrice() external view returns (uint256);
}

/// @dev The precision of the price of the asset in the Alto Lending oracles
uint256 constant LENDING_ORACLE_PRICE_PRECISION = 1e36;

/// @title IOracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This represents the oracle that's used in the Alto Lending
/// @dev This oracle is supposed to return the price of the asset in with LENDING_ORACLE_PRICE_PRECISION precision
interface ILendingOracle is IOracle {
    /// @notice Returns the price of the asset
    /// @return The price of the asset in LENDING_ORACLE_PRICE_PRECISION precision
    /// @dev It will return the price of one unit of the collateral token,
    /// quoted in one unit of the borrow token, scaled by 1e36. It corresponds to the price of
    /// 10^(collateral token decimals) units of the collateral token quoted in
    /// 10^(borrow token decimals) units of the borrow token, with a precision of
    /// (36 + borrow token decimals - collateral token decimals) decimal places.
    function getPrice() external view returns (uint256);
}

/// @dev The precision of the price of the asset in USD oracles
uint256 constant USD_ORACLE_PRICE_PRECISION = 1e8;

/// @title IUsdOracle
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice This represents the oracle that returns the price of the asset in USD
/// @dev This is supposed to return the price of the asset in with USD_ORACLE_PRICE_PRECISION precision
interface IUsdOracle {
    /// @notice Returns the price of the asset in USD
    /// @return The price of the asset in USD in USD_ORACLE_PRICE_PRECISION precision
    /// @dev It will return the price of one unit of the asset, quoted in USD, scaled by USD_ORACLE_PRICE_PRECISION.
    function getPrice() external view returns (uint256);
}

