// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract MockMarket is AltoBaseMarket {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    function initialize(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        );
    }

    function addInterest(uint256 amount) external {
        totalSupply.assets += uint128(amount);
        totalBorrowed.assets += uint128(amount);
    }

    function modifyTotalBorrowed(uint256 amount) external {
        totalBorrowed.assets += uint128(amount);
    }

    function modifyTotalSupply(uint256 amount) external {
        totalSupply.assets += uint128(amount);
    }

    function borrowSharesToAmount(uint256 shares) external view returns (uint256) {
        return shares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
    }

    function borrowAmountToShares(uint256 amount) external view returns (uint256) {
        return amount.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);
    }

    function supplySharesToAssets(uint256 shares) external view returns (uint256) {
        return shares.convertToAssetsDown(totalSupply.assets, totalSupply.shares);
    }

    function calculatePreLiquidationLtv(address user) external view returns (uint256, uint256) {
        uint256 collateralPrice = IOracle(oracle).getPrice();

        // calculate current LTV
        uint256 positionCollateralValue =
            uint256(position[user].collateralAssets).divideWithRounding(collateralPrice, ORACLE_PRICE_PRECISION, false);
        uint256 positionBorrowedAssets =
            uint256(position[user].borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        uint256 currentLtv = positionBorrowedAssets.divideWithPrecisionUp(positionCollateralValue);

        return (currentLtv, _calculateNewLtv(_calculateLiquidationPercentage(currentLtv)));
    }
}

library MockMarketDeployer {
    function deployMarket(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public returns (MockMarket market) {
        market = new MockMarket();

        market.initialize(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        );
    }
}
