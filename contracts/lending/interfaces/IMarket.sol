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
