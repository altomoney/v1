// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMarket} from "./IMarket.sol";

/// @title Alto Borrow Market Interface
/// @custom:contact security@altofoundation.org
/// @notice Interface for an isolated Alto borrow market
interface IAltoBorrowMarket is IMarket {
    /// @notice The maximum amount of assets that can be supplied to the market
    /// @dev A value of zero means that supply is uncapped.
    function supplyCapAssets() external view returns (uint128);

    /// @notice The interest fee in MATH_PRECISION charged on accrued interest
    function interestFee() external view returns (uint256);

    /// @notice Sets the borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 newBorrowOpeningFee) external;

    /// @notice Sets the interest fee
    /// @param newInterestFee The new interest fee
    /// @param skipAccrueInterest Whether to skip accruing interest
    function setInterestFee(uint256 newInterestFee, bool skipAccrueInterest) external;

    /// @notice Sets the maximum amount of assets that can be supplied to the market
    /// @param newSupplyCapAssets The new supply cap in assets
    function setSupplyCap(uint128 newSupplyCapAssets) external;
}
