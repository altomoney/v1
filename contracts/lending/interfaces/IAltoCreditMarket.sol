// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseMarketInitParams, IMarketStaticTypes} from "./IMarket.sol";

/// @notice Struct that represents the parameters for initializing a credit market
struct CreditMarketInitParams {
    /// @notice The parameters for initializing the base market.
    BaseMarketInitParams baseMarketInitParams;
    /// @notice The sole account permitted to own collateral and debt.
    address creditAccount;
    /// @notice The maximum total debt assets permitted for new borrows.
    uint256 creditLimit;
    /// @notice The LTV above which governance may foreclose.
    uint256 foreclosureLtv;
    /// @notice The initial borrow opening fee.
    uint256 initialBorrowOpeningFee;
}

interface IAltoCreditMarketErrors {
    /// @notice Error thrown when a required address is the zero address
    error AltoCreditMarketZeroAddress();

    /// @notice Error thrown when the input is invalid
    error AltoCreditMarketInvalidInput();

    /// @notice Error thrown when an account is unauthorized
    error AltoCreditMarketUnauthorizedAccount();

    /// @notice Error thrown when callback data is provided
    error AltoCreditMarketCallbacksUnsupported();

    /// @notice Error thrown when a borrow would exceed the maximum LTV
    error AltoCreditMarketBorrowingTooMuch();

    /// @notice Error thrown when a borrow would exceed the credit limit
    error AltoCreditMarketCreditLimitExceeded();

    /// @notice Error thrown when the oracle returns a zero price
    error AltoCreditMarketInvalidOraclePrice();

    /// @notice Error thrown when a position is not eligible for foreclosure
    error AltoCreditMarketPositionNotForeclosable();

    /// @notice Error thrown when a standard market operation is unsupported
    error AltoCreditMarketUnsupportedOperation();

    /// @notice Error thrown when public liquidation is attempted
    error AltoCreditMarketNonLiquidatable();

    /// @notice Error thrown when collateral withdrawal is attempted with outstanding debt
    error AltoCreditMarketOutstandingDebt();
}

interface IAltoCreditMarketEvents {
    /// @notice Emitted when the credit limit is set
    /// @param oldCreditLimit The old credit limit
    /// @param newCreditLimit The new credit limit
    event SetCreditLimit(uint256 oldCreditLimit, uint256 newCreditLimit);

    /// @notice Emitted when the foreclosure LTV is set
    /// @param oldForeclosureLtv The old foreclosure LTV
    /// @param newForeclosureLtv The new foreclosure LTV
    event SetForeclosureLtv(uint256 oldForeclosureLtv, uint256 newForeclosureLtv);

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when interest and fees are claimed
    /// @param recipient The account that received the borrow tokens
    /// @param amount The amount of borrow tokens minted
    event InterestClaimed(address indexed recipient, uint256 amount);
}

/// @title Alto Credit Market
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Interface for a single-account mint credit market
interface IAltoCreditMarket is IMarketStaticTypes, IAltoCreditMarketErrors, IAltoCreditMarketEvents {
    /// @notice The sole account permitted to own the market's collateral and debt
    function creditAccount() external view returns (address);

    /// @notice The maximum total debt permitted for new borrows
    function creditLimit() external view returns (uint256);

    /// @notice The LTV above which governance may foreclose
    function foreclosureLtv() external view returns (uint256);

    /// @notice The opening fees and accrued interest available to claim
    function claimableFeesAssets() external view returns (uint128);

    /// @notice Sets the maximum total debt permitted for new borrows
    /// @param newCreditLimit The new credit limit
    function setCreditLimit(uint256 newCreditLimit) external;

    /// @notice Sets the LTV above which governance may foreclose
    /// @param newForeclosureLtv The new foreclosure LTV
    function setForeclosureLtv(uint256 newForeclosureLtv) external;

    /// @notice Sets the borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 newBorrowOpeningFee) external;

    /// @notice Claims interest and fees for the fee recipient
    /// @param interest The amount to claim, or zero to claim all
    /// @return claimed The amount minted to the fee recipient
    function claimInterest(uint256 interest) external returns (uint256 claimed);
}
