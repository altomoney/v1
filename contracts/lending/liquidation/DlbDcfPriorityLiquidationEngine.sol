// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoOwnable2Step, Ownable} from "@alto/utils/AltoOwnable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {Position, IMarket, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {ExpLib, MATH_PRECISION_INT} from "@alto/lending/libraries/ExpLib.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    LiquidationEngineInput,
    LiquidationEngineResult,
    IAltoLiquidationEngine,
    LiquidationEngineType
} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {
    IDcfDlbPriorityLiquidationEngineStaticTypes,
    IDcfDlbPriorityLiquidationEngine,
    IDcfDlbPriorityLiquidationEngineBase,
    IDcfDlbPriorityLiquidationEngineErrors,
    LiquidationConfiguration,
    LiquidablePosition,
    LiquidationCalculation
} from "@alto/lending/liquidation/interfaces/IDcfDlbPriorityLiquidationEngine.sol";
import {IPausable} from "@alto/utils/interfaces/IPausable.sol";

/// @title DlbDcfPriorityLiquidationEngine
/// @dev Dynamic Liquidator Bonus(DLB), Dynamic Close Factor(DCF) and Priority Liquidation Engine
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice Standalone contract for calculating liquidation amounts and fees
contract DlbDcfPriorityLiquidationEngine is AltoOwnable2Step, IDcfDlbPriorityLiquidationEngineStaticTypes {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    /// @inheritdoc IAltoLiquidationEngine
    LiquidationEngineType public constant LIQUIDATION_ENGINE_TYPE = LiquidationEngineType.DLB_DCF_PRIORITY;

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineStaticTypes
    LiquidationConfiguration public liquidationConfiguration;

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineStaticTypes
    mapping(address => LiquidablePosition) public liquidablePositions;

    /// @inheritdoc IAltoLiquidationEngine
    address public market;

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineBase
    mapping(address => bool) public priorityLiquidators;

    /// @notice Constructor for the liquidation engine
    /// @param _owner The owner of the contract
    constructor(address _owner) Ownable(_owner) {
        if (_owner == address(0)) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
    }

    /// @inheritdoc IAltoLiquidationEngine
    function setMarketOnce(address _market) external {
        if (_market == address(0) || market != address(0)) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }

        // Only the market itself can call this function
        if (msg.sender != _market) {
            revert DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();
        }

        market = _market;
        emit SetMarketOnce(_market);
    }

    /// @inheritdoc IAltoLiquidationEngine
    function prepareLiquidation(LiquidationEngineInput memory input)
        external
        returns (LiquidationEngineResult memory result)
    {
        if (msg.sender != market) {
            revert DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();
        }

        // Check if position is solvent (should not be for liquidation)
        if (_isSolvent(input.totalBorrowed, input.position, input.collateralPrice)) {
            revert DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition();
        }

        // Fetch liquidable position from the market
        LiquidablePosition memory liquidablePosition = liquidablePositions[input.borrower];

        // Check if liquidator is a priority liquidator on the market contract
        bool isPriorityLiquidator = priorityLiquidators[input.liquidator];

        LiquidationCalculation memory calc;

        // Initial calculations
        calc.collateralPrice = input.collateralPrice;

        calc.positionCollateralValue = uint256(input.position.collateralAssets)
            .divideWithRounding(calc.collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        calc.positionBorrowedAssets = uint256(input.position.borrowShares)
            .convertToAssetsUp(input.totalBorrowed.assets, input.totalBorrowed.shares);

        calc.currentLtv = calc.positionBorrowedAssets.divideWithPrecisionUp(calc.positionCollateralValue);

        // Calculate liquidation percentage - how far are we between LTV and LLTV from current LTV
        calc.liquidationPercentage = _calculateLiquidationPercentage(calc.currentLtv);

        // Priority liquidation checks
        if (
            liquidationConfiguration.isEnabledPriorityLiquidation
                && calc.currentLtv <= liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        ) {
            if (
                !isPriorityLiquidator
                    && (!liquidablePosition.tagged
                        || block.timestamp - liquidablePosition.timestamp
                            > liquidationConfiguration.liquidationWindowTag)
            ) {
                revert DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();
            }

            // Skip grace period checks for priority liquidators
            if (!isPriorityLiquidator) {
                uint256 gracePeriod = liquidablePosition.tagger == input.liquidator
                    ? liquidationConfiguration.priorityLiquidationGracePeriod
                    : liquidationConfiguration.priorityLiquidationGracePeriod
                        + liquidationConfiguration.taggerLiquidationGracePeriod;

                if (block.timestamp - liquidablePosition.timestamp <= gracePeriod) {
                    revert DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();
                }
            }
        }

        // Apply above to calculate liquidation fee (priority liquidators don't get a bonus fee only base fee)
        calc.liquidationFee = (!isPriorityLiquidator ? _calculateBonusFee(calc.liquidationPercentage) : 0)
            + liquidationConfiguration.liquidationBaseFee;

        // Calculate new LTV - how much LTV are we aiming for after liquidation
        calc.newLtv = _calculateNewLtv(calc.liquidationPercentage, input.maxLtv);

        // Calculate fee in collateral
        calc.liquidatorBonusFee = uint256(input.position.collateralAssets).multiplyWithPrecision(calc.liquidationFee);
        calc.protocolFee = uint256(calc.liquidatorBonusFee)
            .divideWithRounding(liquidationConfiguration.protocolFeePercentage, MATH_PRECISION, true);
        uint256 remainingCollateralAfterFee = input.position.collateralAssets - calc.liquidatorBonusFee;
        calc.remainingCollateralAfterFeeInBorrowAssets =
            remainingCollateralAfterFee.divideWithRounding(calc.collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);

        calc.collateralToSellInBorrowAssets = (calc.positionBorrowedAssets
                - calc.remainingCollateralAfterFeeInBorrowAssets.multiplyWithPrecision(calc.newLtv))
        .divideWithPrecisionUp(MATH_PRECISION - calc.newLtv);
        calc.collateralToSellInBorrowAssets =
            Math.min(calc.collateralToSellInBorrowAssets, calc.remainingCollateralAfterFeeInBorrowAssets);
        calc.collateralToSellInBorrowAssets = Math.min(calc.collateralToSellInBorrowAssets, calc.positionBorrowedAssets);

        // Calculate final amounts
        uint256 totalCollateralToTake = calc.collateralToSellInBorrowAssets
            .divideWithRounding(LENDING_ORACLE_PRICE_PRECISION, calc.collateralPrice, true) + calc.liquidatorBonusFee;
        result.seizedCollateralAssets = totalCollateralToTake > input.position.collateralAssets
            ? input.position.collateralAssets
            : totalCollateralToTake;

        result.repaidBorrowAmount = calc.collateralToSellInBorrowAssets > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : calc.collateralToSellInBorrowAssets;

        result.repaidBorrowShares =
            result.repaidBorrowAmount.convertToSharesDown(input.totalBorrowed.assets, input.totalBorrowed.shares);

        // Ensure we don't try to repay more shares than the user has which can happen since we are using virtual shares
        if (result.repaidBorrowShares.toUint128() > input.position.borrowShares) {
            result.repaidBorrowShares = uint256(input.position.borrowShares);
        }

        result.protocolSeizedCollateralFee = calc.protocolFee;

        delete liquidablePositions[input.borrower];

        return result;
    }

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineBase
    function tagLiquidablePosition(address user, address liquidator) external {
        if (!liquidationConfiguration.isEnabledPriorityLiquidation) {
            revert DcfDlbPriorityLiquidationEnginePriorityLiquidationDisabled();
        }

        if (IMarket(market).paused(PAUSE_TYPE)) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }

        IMarket(market).accrueInterest();

        uint256 collateralPrice = ILendingOracle(IMarket(market).oracle()).getPrice();
        Position memory userPosition = IMarket(market).position(user);
        Balance memory totalBorrowed = IMarket(market).totalBorrowed();

        if (_isSolvent(totalBorrowed, userPosition, collateralPrice)) {
            revert DcfDlbPriorityLiquidationEngineLiquidatingSolventPosition();
        }
        if (priorityLiquidators[liquidator]) {
            revert DcfDlbPriorityLiquidationEngineLiquidationUnauthorized();
        }
        if (liquidablePositions[user].timestamp > 0) {
            if (liquidablePositions[user].timestamp + liquidationConfiguration.liquidationWindowTag >= block.timestamp)
            {
                revert DcfDlbPriorityLiquidationEngineLiquidationAlreadyTagged();
            }
        }
        liquidablePositions[user] = LiquidablePosition({tagged: true, tagger: liquidator, timestamp: block.timestamp});
        emit PositionTagged(user, liquidator, block.timestamp);
    }

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineBase
    function deleteLiquidablePosition(address user) external onlyOwner {
        delete liquidablePositions[user];
    }

    /// @notice Calculates the liquidation percentage - how far are we between LTV and LLTV with position's current LTV
    /// @param currentLtv The current LTV of the position to be liquidated
    /// @return liquidationPercentage The liquidation percentage
    function _calculateLiquidationPercentage(uint256 currentLtv) internal view returns (uint256) {
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
        // liquidationConfiguration.dynamicBonusFeeDecaySteepness is already checked in _validateLiquidationConfiguration
        if (liquidationPercentage < MATH_PRECISION) {
            int256 exponent = -int256(liquidationConfiguration.dynamicBonusFeeDecaySteepness * liquidationPercentage)
                / MATH_PRECISION_INT;
            return liquidationConfiguration.dynamicBonusFeeStart.multiplyWithPrecision(uint256(ExpLib.wExp(exponent)));
        } else {
            return 0;
        }
    }

    /// @notice Calculates the new LTV after liquidation - how much LTV are we aiming for after liquidation
    /// @param liquidationPercentage The liquidation percentage
    /// @param maxLtv The maximum LTV for the market
    /// @return newLtv The new LTV
    function _calculateNewLtv(uint256 liquidationPercentage, uint256 maxLtv) internal view returns (uint256) {
        uint256 liquidationPercentageAppliedPenalty = liquidationPercentage
            < liquidationConfiguration.minPenaltyPercentage
            ? liquidationConfiguration.minPenaltyPercentage
            : liquidationPercentage;

        return maxLtv.multiplyWithPrecision(MATH_PRECISION - liquidationPercentageAppliedPenalty);
    }

    /// @notice Validates the liquidation configuration
    /// @param _liquidationConfiguration The liquidation configuration to validate
    /// @param _maxLtv The max LTV for validation
    /// @param _feeRecipient The fee recipient address for validation
    function _validateLiquidationConfiguration(
        LiquidationConfiguration memory _liquidationConfiguration,
        uint256 _maxLtv,
        address _feeRecipient
    ) internal pure {
        if (_liquidationConfiguration.maxLiquidationLtv < _maxLtv) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation < _liquidationConfiguration.maxLiquidationLtv) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation > MATH_PRECISION) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeDecaySteepness > 100 * MATH_PRECISION
                || _liquidationConfiguration.dynamicBonusFeeDecaySteepness == 0
        ) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeStart + _liquidationConfiguration.liquidationBaseFee > 0.15 ether
                || _liquidationConfiguration.dynamicBonusFeeStart + _liquidationConfiguration.liquidationBaseFee
                    > 1 ether - _liquidationConfiguration.maxLiquidationLtv
        ) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.minPenaltyPercentage > MATH_PRECISION) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (
            _liquidationConfiguration.protocolFeePercentage > MATH_PRECISION
                || (_liquidationConfiguration.protocolFeePercentage > 0 && _feeRecipient == address(0))
        ) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.priorityLiquidationGracePeriod > 1 hours) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.taggerLiquidationGracePeriod > 30 minutes) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (_liquidationConfiguration.liquidationWindowTag > 3 days) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
        if (
            _liquidationConfiguration.priorityLiquidationGracePeriod
                    + _liquidationConfiguration.taggerLiquidationGracePeriod
                > _liquidationConfiguration.liquidationWindowTag
        ) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }
    }

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineBase
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external onlyOwner {
        _validateLiquidationConfiguration(
            _liquidationConfiguration, IMarket(market).maxLtv(), IMarket(market).feeRecipient()
        );

        emit SetLiquidationConfiguration(liquidationConfiguration, _liquidationConfiguration);
        liquidationConfiguration = _liquidationConfiguration;
    }

    /// @inheritdoc IDcfDlbPriorityLiquidationEngineBase
    function setPriorityLiquidator(address liquidator, bool status) external onlyOwner {
        if (liquidator == address(0)) {
            revert DcfDlbPriorityLiquidationEngineInvalidInput();
        }

        priorityLiquidators[liquidator] = status;
        emit PriorityLiquidatorUpdated(liquidator, status);
    }

    /// @inheritdoc IAltoLiquidationEngine
    function minLltv() external view returns (uint256) {
        return liquidationConfiguration.maxLiquidationLtv;
    }

    /// @inheritdoc IAltoLiquidationEngine
    function protocolFeePercentage() external view returns (uint256) {
        return liquidationConfiguration.protocolFeePercentage;
    }

    /// @dev Returns true if the user's position is solvent based on the max LTV of the market.
    /// @param totalBorrowed The total borrowed amount of the market
    /// @param position The position of the user
    /// @param collateralPrice The price of the collateral
    function _isSolvent(Balance memory totalBorrowed, Position memory position, uint256 collateralPrice)
        internal
        view
        returns (bool)
    {
        uint256 collateralValue = uint256(position.collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(liquidationConfiguration.maxLiquidationLtv);
        uint256 borrowValue =
            uint256(position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return borrowValue == 0 || maxBorrowValue > borrowValue;
    }
}

