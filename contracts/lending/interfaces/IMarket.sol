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

interface IMarketBase is IAuth {
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function borrowToken() external view returns (address);
    function collateralToken() external view returns (address);

    function addSupply(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);

    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256);

    function addCollateral(uint256 assets, address onBehalf) external returns (uint256);

    function removeCollateral(uint256 assets, address onBehalf, address receiver) external returns (uint256);

    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256);

    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256);
}

interface IMarket is IMarketBase {
    function position(address user) external view returns (Position memory);

    function totalSupply() external view returns (Balance memory);

    function totalBorrowed() external view returns (Balance memory);
}

interface IMarkeStaticTypes is IMarketBase {
    function position(address user)
        external
        view
        returns (uint128 supplyShares, uint128 borrowShares, uint128 collateralAssets);

    function totalSupply() external view returns (uint128 assets, uint128 shares);

    function totalBorrowed() external view returns (uint128 assets, uint128 shares);
}
