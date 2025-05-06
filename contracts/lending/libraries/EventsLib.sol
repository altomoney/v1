// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title EventsLib
/// @author Tapioca DAO
/// @notice Library exposing events for the lending protocol.
library EventsLib {
    /// @notice Emitted when a user supplies tokens to the lending market
    /// @param caller The address of the caller who is supplying tokens
    /// @param onBehalf The address of the user who is receiving the ownership of supplied tokens
    /// @param assets The amount of assets supplied
    /// @param shares The amount of shares minted
    event AddSupply(address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws tokens from the lending market
    /// @param caller The address of the caller who is withdrawing tokens on behalf
    /// @param onBehalf The address of the user who is the owner of withdrawn tokens
    /// @param receiver The address of the user who is receiving the withdrawn tokens
    /// @param assets The amount of assets withdrawn
    /// @param shares The amount of shares burned
    event RemoveSupply(
        address indexed caller, address indexed onBehalf, address indexed receiver, uint256 assets, uint256 shares
    );

    /// @notice Emitted when a user borrows tokens from the lending market
    /// @param caller The address of the caller who is borrowing tokens
    /// @param onBehalf The address of the user who is the owner of borrowed tokens
    /// @param receiver The address of the user who is receiving the borrowed tokens
    /// @param assets The amount of assets borrowed
    /// @param shares The amount of shares minted
    event Borrow(
        address indexed caller, address indexed onBehalf, address indexed receiver, uint256 assets, uint256 shares
    );

    /// @notice Emitted when a user repays borrowed tokens
    /// @param caller The address of the caller who is repaying tokens
    /// @param onBehalf The address of the user who is the owner of the borrow position
    /// @param assets The amount of assets repaid
    /// @param shares The amount of shares burned
    event Repay(address indexed caller, address indexed onBehalf, uint256 assets, uint256 shares);

    /// @notice Emitted when a user deposits collateral
    /// @param caller The address of the caller who is supplying collateral
    /// @param onBehalf The address of the user who is the owner of supplied collateral
    /// @param amount The amount of collateral supplied
    event AddCollateral(address indexed caller, address indexed onBehalf, uint256 amount);

    /// @notice Emitted when a user withdraws collateral
    /// @param caller The address of the caller who is withdrawing collateral
    /// @param onBehalf The address of the owner of collateral being withdrawn
    /// @param receiver The address of the user who is receiving the withdrawn collateral
    /// @param amount The amount of collateral withdrawn
    event RemoveCollateral(address indexed caller, address indexed onBehalf, address indexed receiver, uint256 amount);

    /// @notice Emitted when interest is accrued
    /// @param borrowRate The average rate
    /// @param interest The amount of interest accrued
    /// @param totalBorrowAssets The total borrow assets
    /// @param totalSupplyAssets The total supply assets
    event AccrueInterest(uint256 borrowRate, uint256 interest, uint128 totalBorrowAssets, uint128 totalSupplyAssets);

    /// @notice Emitted when a position is liquidated
    /// @param liquidator The address performing the liquidation
    /// @param borrower The address of the borrower being liquidated
    /// @param repayAmount The amount of borrow token repaid
    /// @param repayShares The amount of borrow shares repaid/burned
    /// @param seizedCollateralAmount The amount of collateral seized by the liquidator
    event Liquidate(
        address indexed liquidator,
        address indexed borrower,
        uint256 repayAmount,
        uint256 repayShares,
        uint256 seizedCollateralAmount
    );
}
