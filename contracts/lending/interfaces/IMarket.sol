// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuth} from "@alto-monorepo/utils/interfaces/common/IAuth.sol";

struct Balance {
    uint128 assets;
    uint128 shares;
}

struct Position {
    uint128 supplyShares;
    uint128 borrowShares;
    uint128 collateralAssets;
}

struct LiquidationConfiguration {
    uint256 maxLiquidationLtv;
    uint256 dynamicBonusFeeStart;
    uint256 ltvForCompleteLiquidation;
    uint256 dynamicBonusFeeDecaySteepness;
    uint256 liquidationBaseFee;
    uint256 minPenaltyPercentage;
}

struct LiquidationResult {
    uint256 currentLtv;
    uint256 newLtv;
    uint256 optimalRepayAmount;
    uint256 collateralAmount;
}

struct LiquidationCalculation {
    uint256 collateralPrice;
    uint256 positionCollateralValue;
    uint256 positionBorrowedAssets;
    uint256 currentLtv;
    uint256 liquidationPercentage;
    uint256 liquidationFee;
    uint256 newLtv;
    uint256 liquidatorBonusFee;
    uint256 remainingCollateralValue;
    uint256 collateralToSell;
    uint256 expectedRepayAmount;
}

interface IMarketErrors {
    error AltoBorrowMarketInvalidInput();
    error AltoBorrowMarketInsufficientUserCollateral();
    error AltoBorrowMarketBorrowingTooMuch();
    error AltoBorrowMarketInsufficientMarketLiquidity();
    error AltoBorrowMarketLiquidatingHealthyPosition();
    error AltoBorrowMarketUnauthorized();
}

interface IMarketEvents {
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
    /// @param feeAmount The amount of assets paid as opening fee
    /// @param feeSupplyShares The amount of supply shares given to the fee recipient
    event Borrow(
        address indexed caller,
        address indexed onBehalf,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 feeAmount,
        uint256 feeSupplyShares
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

interface IMarketBase is IMarketErrors, IMarketEvents, IAuth {
    function borrowToken() external view returns (address);
    function collateralToken() external view returns (address);

    function addSupply(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256);

    function addCollateral(uint256 assets, address onBehalf) external returns (uint256);

    function removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata data)
        external
        returns (uint256);

    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata data)
        external
        returns (uint256, uint256, uint256);

    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    function accrueInterest() external;

    function setIrm(address irm) external;

    function borrowOpeningFee() external view returns (uint256);

    function maxLtv() external view returns (uint256);

    function setAuthorizedCallback(address callback, bool isAuthorized) external;
}

interface IMarket is IMarketBase {
    function position(address user) external view returns (Position memory);

    function totalSupply() external view returns (Balance memory);

    function totalBorrowed() external view returns (Balance memory);
}

interface IMarketStaticTypes is IMarketBase {
    function position(address user)
        external
        view
        returns (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets);

    function totalSupply() external view returns (uint128 assets, uint128 shares);

    function totalBorrowed() external view returns (uint128 assets, uint128 shares);
}
