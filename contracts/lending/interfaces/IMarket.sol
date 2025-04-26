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
}

interface IMarketEvents {
    /// @notice Emitted when a user supplies tokens to the lending market
    /// @param user The address of the user who supplied tokens
    /// @param assets The amount of assets supplied
    /// @param shares The amount of shares minted
    event AddSupply(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws tokens from the lending market
    /// @param user The address of the user who withdrew tokens
    /// @param assets The amount of assets withdrawn
    /// @param shares The amount of shares burned
    event RemoveSupply(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user borrows tokens from the lending market
    /// @param user The address of the user who borrowed tokens
    /// @param assets The amount of assets borrowed
    /// @param shares The amount of shares minted
    event Borrow(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user repays borrowed tokens
    /// @param user The address of the user who repaid tokens
    /// @param assets The amount of assets repaid
    /// @param shares The amount of shares burned
    event Repay(address indexed user, uint256 assets, uint256 shares);

    /// @notice Emitted when a user deposits collateral
    /// @param user The address of the user who deposited collateral
    /// @param amount The amount of collateral deposited
    event AddCollateral(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws collateral
    /// @param user The address of the user who withdrew collateral
    /// @param amount The amount of collateral withdrawn
    event RemoveCollateral(address indexed user, uint256 amount);

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

interface IMarket is IMarketErrors, IMarketEvents {}