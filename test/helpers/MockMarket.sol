// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {IOracle} from "@alto/oracles/interfaces/IOracle.sol";
import {LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {BaseMarketInitParams, BorrowMarketInitParams, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {DlbDcfPriorityLiquidationEngine} from "@alto/lending/liquidation/DlbDcfPriorityLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngine,
    LiquidationConfiguration
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract MockMarket is AltoBaseMarket {
    using AssetShareConversionMath for uint256;
    using FixedPointMath for uint256;

    uint256 private _borrowOpeningFee;

    function initialize(BaseMarketInitParams memory _baseMarketInitParams, uint256 _borrowOpeningFeeWad)
        public
        initializer
    {
        __AltoBaseMarket_init(_baseMarketInitParams, MarketType.BORROW);

        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_baseMarketInitParams.feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBaseMarketInvalidInput();
        }
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
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

    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function setBorrowOpeningFee(uint256 _borrowOpeningFeeWad) external onlyOwner {
        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBaseMarketInvalidInput();
        }
        // emit SetBorrowOpeningFee(_borrowOpeningFee, _borrowOpeningFeeWad);
        _borrowOpeningFee = _borrowOpeningFeeWad;
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
        uint256 positionCollateralValue = uint256(position[user].collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 positionBorrowedAssets =
            uint256(position[user].borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        uint256 currentLtv = positionBorrowedAssets.divideWithPrecisionUp(positionCollateralValue);

        return (currentLtv, _calculateNewLtv(_calculateLiquidationPercentage(currentLtv), maxLtv));
    }

    function calculateLiquidatorAndProtocolFee(address user, bool isPriorityLiquidator)
        external
        view
        returns (uint256, uint256)
    {
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        (uint256 currentLtv, uint256 newLtv) = this.calculatePreLiquidationLtv(user);
        uint256 bonusFee = !isPriorityLiquidator ? _calculateBonusFee(_calculateLiquidationPercentage(currentLtv)) : 0;
        uint256 liquidatorFee = uint256(position[user].collateralAssets)
            .multiplyWithPrecision(bonusFee + liquidationConfiguration.liquidationBaseFee);

        uint256 protocolFee = uint256(liquidatorFee)
            .divideWithRounding(liquidationConfiguration.protocolFeePercentage, MATH_PRECISION, true);

        return (liquidatorFee, protocolFee);
    }

    /// @notice Calculates the liquidation percentage - how far are we between LTV and LLTV with position's current LTV
    /// @param currentLtv The current LTV of the position to be liquidated
    /// @return liquidationPercentage The liquidation percentage
    function _calculateLiquidationPercentage(uint256 currentLtv) internal view returns (uint256) {
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        if (currentLtv >= liquidationConfiguration.ltvForCompleteLiquidation) {
            return MATH_PRECISION;
        } else {
            return (currentLtv - liquidationConfiguration.maxLiquidationLtv)
            .divideWithPrecisionUp(
                liquidationConfiguration.ltvForCompleteLiquidation - liquidationConfiguration.maxLiquidationLtv
            );
        }
    }

    /// @notice Calculates the bonus fee for the liquidation - used to incentivize fast liquidators
    /// @param liquidationPercentage The liquidation percentage
    /// @return bonusFee The bonus fee
    function _calculateBonusFee(uint256 liquidationPercentage) internal view returns (uint256) {
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        // liquidationConfiguration.dynamicBonusFeeDecaySteepness is already checked in _validateLiquidationConfiguration
        if (liquidationPercentage >= MATH_PRECISION) {
            return 0;
        }
        uint256 base = MATH_PRECISION - liquidationPercentage;
        uint256 decay = FixedPointMathLib.rpow(
            base, liquidationConfiguration.dynamicBonusFeeDecaySteepness / MATH_PRECISION, MATH_PRECISION
        );
        return liquidationConfiguration.dynamicBonusFeeStart.multiplyWithPrecision(decay);
    }

    /// @notice Calculates the new LTV after liquidation - how much LTV are we aiming for after liquidation
    /// @param liquidationPercentage The liquidation percentage
    /// @param maxLtv The maximum LTV for the market
    /// @return newLtv The new LTV
    function _calculateNewLtv(uint256 liquidationPercentage, uint256 maxLtv) internal view returns (uint256) {
        LiquidationConfiguration memory liquidationConfiguration =
            IDcfDlbPriorityLiquidationEngine(liquidationEngine).liquidationConfiguration();
        uint256 liquidationPercentageAppliedPenalty = liquidationPercentage
            < liquidationConfiguration.minPenaltyPercentage
            ? liquidationConfiguration.minPenaltyPercentage
            : liquidationPercentage;

        return maxLtv.multiplyWithPrecision(MATH_PRECISION - liquidationPercentageAppliedPenalty);
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
        address liquidationEngine = address(new DlbDcfPriorityLiquidationEngine(address(this)));

        market = new MockMarket();

        market.initialize(
            BaseMarketInitParams({
                borrowToken: _borrowToken,
                collateralToken: _collateralToken,
                irm: _irm,
                owner: _owner,
                oracle: _oracle,
                maxLtv: _maxLtv,
                feeRecipient: _feeRecipient,
                liquidationEngine: liquidationEngine
            }),
            _borrowOpeningFee
        );

        IDcfDlbPriorityLiquidationEngine(liquidationEngine).setLiquidationConfiguration(_liquidationConfiguration);
    }
}
