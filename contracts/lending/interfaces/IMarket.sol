// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuth} from "@alto/utils/interfaces/IAuth.sol";

struct Balance {
    uint128 assets;
    uint128 shares;
}

struct Position {
    uint128 supplyShares;
    uint128 borrowShares;
    uint128 collateralAssets;
}

struct LiquidablePosition {
    bool tagged;
    address tagger;
    uint256 timestamp;
}

struct LiquidationConfiguration {
    uint256 maxLiquidationLtv;
    uint256 dynamicBonusFeeStart;
    uint256 ltvForCompleteLiquidation;
    uint256 dynamicBonusFeeDecaySteepness;
    uint256 liquidationBaseFee;
    uint256 minPenaltyPercentage;
    uint32 priorityLiquidationGracePeriod;
    uint32 taggerLiquidationGracePeriod;
    uint32 liquidationWindowTag;
}

struct LiquidationCalculation {
    uint256 collateralPrice;
    uint256 positionCollateralValue;
    uint256 positionBorrowedAssets;
    uint256 liquidationPercentage;
    uint256 liquidationFee;
    uint256 newLtv;
    uint256 liquidatorBonusFee;
    uint256 remainingCollateralAfterFeeInBorrowAssets;
}
//uint256 collateralToSell;
// uint256 expectedRepayAmount;

interface IMarketErrors {
    error AltoBorrowMarketInvalidInput();
    error AltoBorrowMarketInsufficientUserCollateral();
    error AltoBorrowMarketBorrowingTooMuch();
    error AltoBorrowMarketInsufficientMarketLiquidity();
    error AltoBorrowMarketLiquidatingHealthyPosition();
    error AltoBorrowMarketUnauthorized();
    error AltoBorrowMarketLiquidationUnauthorized();
    error AltoBorrowMarketLiquidationAlreadyTagged();
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

    /// @notice Emitted when a position is tagged for liquidation
    /// @param user The address of the user whose position was tagged
    /// @param tagger The address of the liquidator who tagged the position
    /// @param timestamp The timestamp when the position was tagged
    event PositionTagged(address indexed user, address indexed tagger, uint256 timestamp);

    /// @notice Emitted when a priority liquidator's status is updated
    /// @param liquidator The address of the liquidator
    /// @param status The new status of the liquidator
    event PriorityLiquidatorUpdated(address indexed liquidator, bool status);

    // add liquidation event
    /// @notice Emitted when a liquidation occurs
    /// @param user The address of the user whose position was liquidated
    /// @param collateralToken The address of the collateral token
    /// @param borrowToken The address of the borrow token
    /// @param liquidator The address of the liquidator
    /// @param liquidatedCollateral The amount of collateral that was liquidated
    /// @param repaidBorrow The amount of borrow tokens that were repaid
    /// @param repaidBorrowShares The amount of borrow shares that were repaid
    /// @param badDebtClearedAssets The amount of bad debt cleared
    /// @param badDebtClearedShares The amount of bad debt shares cleared
    event Liquidation(
        address indexed user,
        address collateralToken,
        address borrowToken,
        address liquidator,
        uint256 liquidatedCollateral,
        uint256 repaidBorrow,
        uint256 repaidBorrowShares,
        uint256 badDebtClearedAssets,
        uint256 badDebtClearedShares
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

    function setPriorityLiquidator(address liquidator, bool status) external;

    function tagLiquidablePosition(address user, address liquidator) external;

    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external;
}

interface IMarket is IMarketBase {
    function position(address user) external view returns (Position memory);

    function totalSupply() external view returns (Balance memory);

    function totalBorrowed() external view returns (Balance memory);

    function liquidablePositions(address user) external view returns (LiquidablePosition memory);

    function liquidationConfiguration() external view returns (LiquidationConfiguration memory);
}

interface IMarketStaticTypes is IMarketBase {
    function position(address user)
        external
        view
        returns (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets);

    function totalSupply() external view returns (uint128 assets, uint128 shares);

    function totalBorrowed() external view returns (uint128 assets, uint128 shares);

    function liquidablePositions(address user) external view returns (bool tagged, address tagger, uint256 timestamp);

    function liquidationConfiguration()
        external
        view
        returns (
            uint256 maxLiquidationLtv,
            uint256 dynamicBonusFeeStart,
            uint256 ltvForCompleteLiquidation,
            uint256 dynamicBonusFeeDecaySteepness,
            uint256 liquidationBaseFee,
            uint256 minPenaltyPercentage,
            uint32 priorityLiquidationGracePeriod,
            uint32 taggerLiquidationGracePeriod,
            uint32 liquidationWindowTag
        );
}
