// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";

import {Position, IMarket, IMarketErrors, IMarketStaticTypes, Balance} from "@alto/lending/interfaces/IMarket.sol";
import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {ExpLib, MATH_PRECISION_INT} from "@alto/lending/libraries/ExpLib.sol";
import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";
import {
    LiquidationEngineInput,
    LiquidationEngineResult,
    IAltoLiquidationEngine
} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {
    IPriorityLiquidationEngineStaticTypes,
    IPriorityLiquidationEngine,
    IPriorityLiquidationEngineBase,
    LiquidationConfiguration,
    LiquidablePosition,
    LiquidationCalculation
} from "@alto/lending/interfaces/IPriorityLiquidationEngine.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";

/// @title Alto Liquidation Engine
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice Standalone contract for calculating liquidation amounts and fees
contract AltoLiquidationEngine is Ownable2Step, IPriorityLiquidationEngineStaticTypes, Pausable {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    /// @notice Error thrown when the input is invalid
    error AltoLiquidationEngineInvalidInput();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error AltoLiquidationEnginePriorityLiquidationDisabled();

    /// @notice Error thrown when executor is not allowed to perform liquidation at this time
    error AltoLiquidationEngineLiquidationUnauthorized();

    /// @inheritdoc IPriorityLiquidationEngineStaticTypes
    LiquidationConfiguration public liquidationConfiguration;

    /// @inheritdoc IPriorityLiquidationEngineStaticTypes
    mapping(address => LiquidablePosition) public liquidablePositions;

    /// @inheritdoc IAltoLiquidationEngine
    address public immutable MARKET;

    /// @inheritdoc IPriorityLiquidationEngineBase
    mapping(address => bool) public priorityLiquidators;

    /// @notice Constructor for the liquidation engine
    /// @param _owner The owner of the contract
    /// @param _market The market address
    constructor(address _owner, address _market) Ownable(_owner) {
        if (_owner == address(0) || _market == address(0)) {
            revert AltoLiquidationEngineInvalidInput();
        }

        MARKET = _market;

        _setPauser(_owner, PAUSE_TYPE, true);
    }

    /// @dev Modifier to check if the market is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @inheritdoc IAltoLiquidationEngine
    function prepareLiquidation(LiquidationEngineInput memory input)
        external
        returns (LiquidationEngineResult memory result)
    {
        // Check if position is solvent (should not be for liquidation)
        if (isSolvent(input.borrower)) {
            revert AltoBaseMarketLiquidatingSolventPosition();
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
                revert AltoBaseMarketLiquidationUnauthorized();
            }

            // Skip grace period checks for priority liquidators
            if (!isPriorityLiquidator) {
                uint256 gracePeriod = liquidablePosition.tagger == input.liquidator
                    ? liquidationConfiguration.priorityLiquidationGracePeriod
                    : liquidationConfiguration.priorityLiquidationGracePeriod
                        + liquidationConfiguration.taggerLiquidationGracePeriod;

                if (block.timestamp - liquidablePosition.timestamp <= gracePeriod) {
                    revert AltoBaseMarketLiquidationUnauthorized();
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

    /// @inheritdoc IPriorityLiquidationEngineBase
    function tagLiquidablePosition(address user, address liquidator) external whenNotPaused {
        if (!liquidationConfiguration.isEnabledPriorityLiquidation) {
            revert AltoBaseMarketPriorityLiquidationDisabled();
        }

        IMarket(MARKET).accrueInterest();

        if (isSolvent(user)) {
            revert AltoBaseMarketLiquidatingSolventPosition();
        }
        if (priorityLiquidators[liquidator]) {
            revert AltoBaseMarketLiquidationUnauthorized();
        }
        if (liquidablePositions[user].timestamp > 0) {
            if (liquidablePositions[user].timestamp + liquidationConfiguration.liquidationWindowTag >= block.timestamp)
            {
                revert AltoBaseMarketLiquidationAlreadyTagged();
            }
        }
        liquidablePositions[user] = LiquidablePosition({tagged: true, tagger: liquidator, timestamp: block.timestamp});
        emit PositionTagged(user, liquidator, block.timestamp);
    }

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
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation < _liquidationConfiguration.maxLiquidationLtv) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeDecaySteepness > 100 * MATH_PRECISION
                || _liquidationConfiguration.dynamicBonusFeeDecaySteepness == 0
        ) {
            revert AltoBaseMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeStart + _liquidationConfiguration.liquidationBaseFee > 0.15 ether
                || _liquidationConfiguration.dynamicBonusFeeStart + _liquidationConfiguration.liquidationBaseFee
                    > 1 ether - _liquidationConfiguration.maxLiquidationLtv
        ) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.minPenaltyPercentage > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.protocolFeePercentage > MATH_PRECISION
                || (_liquidationConfiguration.protocolFeePercentage > 0 && _feeRecipient == address(0))
        ) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.priorityLiquidationGracePeriod > 1 hours) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.taggerLiquidationGracePeriod > 30 minutes) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_liquidationConfiguration.liquidationWindowTag > 3 days) {
            revert AltoBaseMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.priorityLiquidationGracePeriod
                    + _liquidationConfiguration.taggerLiquidationGracePeriod
                > _liquidationConfiguration.liquidationWindowTag
        ) {
            revert AltoBaseMarketInvalidInput();
        }
    }

    /// @inheritdoc IPriorityLiquidationEngineBase
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external onlyOwner {
        _validateLiquidationConfiguration(
            _liquidationConfiguration, IMarketStaticTypes(MARKET).maxLtv(), IMarketStaticTypes(MARKET).feeRecipient()
        );

        emit SetLiquidationConfiguration(liquidationConfiguration, _liquidationConfiguration);
        liquidationConfiguration = _liquidationConfiguration;
    }

    /// @inheritdoc IPriorityLiquidationEngineBase
    function setPriorityLiquidator(address liquidator, bool status) external onlyOwner {
        if (liquidator == address(0)) {
            revert AltoBaseMarketInvalidInput();
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

    function isSolvent(address user) public view returns (bool) {
        uint256 collateralPrice = ILendingOracle(IMarket(MARKET).oracle()).getPrice();
        Position memory userPosition = IMarket(MARKET).position(user);
        Balance memory totalBorrowed = IMarket(MARKET).totalBorrowed();
        uint256 collateralValue = uint256(userPosition.collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(liquidationConfiguration.maxLiquidationLtv);
        uint256 borrowValue =
            uint256(userPosition.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return borrowValue == 0 || maxBorrowValue > borrowValue;
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status) external override onlyOwner {
        if (pauseType != PAUSE_TYPE) {
            revert AltoBaseMarketInvalidInput();
        }

        _setPauser(pauser, pauseType, status);
    }
}

