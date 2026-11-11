// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMarket, IMarketStaticTypes} from "./IMarket.sol";

interface IAltoBorrowMarketErrors {
    /// @notice Thrown when the input is invalid
    error AltoBorrowMarketInvalidInput();

    /// @notice Thrown when the supply cap is exceeded
    error AltoBorrowMarketSupplyCapExceeded();
}

interface IAltoBorrowMarketEvents {
    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when the supply cap is set
    /// @param oldSupplyCapAssets The old supply cap assets
    /// @param newSupplyCapAssets The new supply cap assets
    event SetSupplyCap(uint128 oldSupplyCapAssets, uint128 newSupplyCapAssets);

    /// @notice Emitted when the interest fee is set
    /// @param oldInterestFee The old interest fee
    /// @param newInterestFee The new interest fee
    event SetInterestFee(uint256 oldInterestFee, uint256 newInterestFee);

    /// @notice Emitted when interest fee is accrued
    /// @param recipient The recipient of the interest fee
    /// @param interest The amount of interest accrued
    /// @param feeShares The amount of fee shares accrued
    event InterestFeeAccrued(address indexed recipient, uint256 interest, uint256 feeShares);
}

/// @dev This interface is used for factorizing IAltoBorrowMarketStaticTypes and IAltoBorrowMarket.
/// @dev Consider using the IAltoBorrowMarket interface instead of this one.
interface IAltoBorrowMarketBase is IAltoBorrowMarketErrors, IAltoBorrowMarketEvents {
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

/// @title Alto Borrow Market Interface
/// @custom:contact security@altofoundation.org
/// @notice Interface for an isolated Alto borrow market
interface IAltoBorrowMarket is IMarket, IAltoBorrowMarketBase {}

/// @dev This interface is inherited by the implementation so public struct getters are type checked.
/// @dev Consider using the IAltoBorrowMarket interface instead of this one.
interface IAltoBorrowMarketStaticTypes is IMarketStaticTypes, IAltoBorrowMarketBase {}
