// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {
    Balance,
    Position,
    LiquidationConfiguration,
    LiquidationCalculation,
    LiquidablePosition
} from "@alto/lending/interfaces/IMarket.sol";
import {Auth} from "@alto/utils/Auth.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

import {ExpLib, MATH_PRECISION_INT} from "./libraries/ExpLib.sol";
import {FixedPointMath, MATH_PRECISION} from "./libraries/FixedPointMath.sol";
import {Uint128Converter} from "./libraries/Uint128Converter.sol";

import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IMarketStaticTypes, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {
    IBorrowCallback,
    IRemoveCollateralCallback,
    ILiquidateCallback
} from "@alto/lending/interfaces/IMarketCallbacks.sol";

/// @title Alto Borrow Market
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
/// @notice An Isolated Borrow Market
contract AltoBorrowMarket is Auth, Pausable, IMarketStaticTypes {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    using SafeERC20 for IERC20;

    /// @inheritdoc IMarketBase
    address public borrowToken;

    /// @inheritdoc IMarketBase
    address public collateralToken;

    /// @inheritdoc IMarketStaticTypes
    Balance public totalSupply;

    /// @inheritdoc IMarketStaticTypes
    Balance public totalBorrowed;

    /// @inheritdoc IMarketStaticTypes
    mapping(address => Position) public position;

    /// @inheritdoc IMarketBase
    mapping(address => bool) public authorizedCallbacks;

    /// @inheritdoc IMarketBase
    mapping(address => bool) public priorityLiquidators;

    /// @inheritdoc IMarketStaticTypes
    mapping(address => LiquidablePosition) public liquidablePositions;

    /// @inheritdoc IMarketBase
    address public irm;

    /// @inheritdoc IMarketBase
    address public oracle;

    /// @inheritdoc IMarketBase
    uint256 public maxLtv;

    /// @inheritdoc IMarketStaticTypes
    LiquidationConfiguration public liquidationConfiguration;

    /// @inheritdoc IMarketBase
    uint256 public borrowOpeningFee;

    /// @inheritdoc IMarketBase
    address public feeRecipient;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) Ownable(_owner) {
        _validateLiquidationConfiguration(_liquidationConfiguration, _maxLtv);

        if (_borrowToken == address(0) || _collateralToken == address(0) || _oracle == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_maxLtv > MATH_PRECISION || _borrowOpeningFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_feeRecipient == address(0) && _borrowOpeningFee > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        borrowToken = _borrowToken;
        collateralToken = _collateralToken;
        irm = _irm;
        oracle = _oracle;
        maxLtv = _maxLtv;
        liquidationConfiguration = _liquidationConfiguration;
        borrowOpeningFee = _borrowOpeningFee;
        feeRecipient = _feeRecipient;

        if (irm != address(0)) {
            IIrm(irm).setMarket(address(this));
        }
    }

    /// @inheritdoc IMarketBase
    function setIrm(address _irm) external onlyOwner {
        _accrueInterest();

        emit SetIrm(irm, _irm);
        irm = _irm;

        if (irm != address(0)) {
            IIrm(irm).setMarket(address(this));
        }
    }

    /// @inheritdoc IMarketBase
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetOracle(oracle, _oracle);
        oracle = _oracle;
    }

    /// @inheritdoc IMarketBase
    function setMaxLtv(uint256 _maxLtv) external onlyOwner {
        if (_maxLtv > MATH_PRECISION || _maxLtv > liquidationConfiguration.maxLiquidationLtv) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetMaxLtv(maxLtv, _maxLtv);
        maxLtv = _maxLtv;
    }

    /// @inheritdoc IMarketBase
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration)
        external
        onlyOwner
    {
        _validateLiquidationConfiguration(_liquidationConfiguration, maxLtv);

        emit SetLiquidationConfiguration(liquidationConfiguration, _liquidationConfiguration);
        liquidationConfiguration = _liquidationConfiguration;
    }

    function _validateLiquidationConfiguration(
        LiquidationConfiguration memory _liquidationConfiguration,
        uint256 _maxLtv
    ) internal pure {
        if (_liquidationConfiguration.maxLiquidationLtv < _maxLtv) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation < _liquidationConfiguration.maxLiquidationLtv) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.ltvForCompleteLiquidation > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeDecaySteepness > 100 * MATH_PRECISION
                || _liquidationConfiguration.dynamicBonusFeeDecaySteepness == 0
        ) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.dynamicBonusFeeStart + _liquidationConfiguration.liquidationBaseFee
                > MATH_PRECISION
        ) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.minPenaltyPercentage > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.priorityLiquidationGracePeriod > 1 hours) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.taggerLiquidationGracePeriod > 30 minutes) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_liquidationConfiguration.liquidationWindowTag > 3 days) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (
            _liquidationConfiguration.priorityLiquidationGracePeriod
                + _liquidationConfiguration.taggerLiquidationGracePeriod > _liquidationConfiguration.liquidationWindowTag
        ) {
            revert AltoBorrowMarketInvalidInput();
        }
    }

    /// @inheritdoc IMarketBase
    function setBorrowOpeningFee(uint256 _borrowOpeningFee) external onlyOwner {
        if (_borrowOpeningFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(borrowOpeningFee, _borrowOpeningFee);
        borrowOpeningFee = _borrowOpeningFee;
    }

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _feeRecipient) external virtual onlyOwner {
        if (_feeRecipient == address(0) && borrowOpeningFee > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IMarketBase
    function setAuthorizedCallback(address callback, bool value) external onlyOwner {
        if (callback == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        authorizedCallbacks[callback] = value;
        emit SetAuthorizedCallback(callback, value);
    }

    /// @inheritdoc IMarketBase
    function addSupply(uint256 assets, uint256 shares, address onBehalf)
        external
        virtual
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares) || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsUp(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.convertToSharesDown(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets += assets.toUint128();
        totalSupply.shares += shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);
        position[onBehalf].supplyShares += shares.toUint128();

        emit AddSupply(msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        virtual
        whenNotPaused
        returns (uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares) || receiver == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBorrowMarketUnauthorized();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsDown(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.convertToSharesUp(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets -= assets.toUint128();
        totalSupply.shares -= shares.toUint128();

        _sendBorrowToken(address(this), receiver, assets);
        position[onBehalf].supplyShares -= shares.toUint128();

        emit RemoveSupply(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function addCollateral(uint256 assets, address onBehalf) external whenNotPaused whenNotFrozen returns (uint256) {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        position[onBehalf].collateralAssets += assets.toUint128();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        emit AddCollateral(msg.sender, onBehalf, assets);

        return (assets);
    }

    /// @inheritdoc IMarketBase
    function removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata data)
        external
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBorrowMarketUnauthorized();
        }

        _accrueInterest();

        position[onBehalf].collateralAssets -= assets.toUint128();

        IERC20(collateralToken).safeTransfer(receiver, assets);

        if (authorizedCallbacks[receiver] && data.length > 0) {
            IRemoveCollateralCallback(receiver).onRemoveCollateralCallback(assets, data);
        } else if (data.length > 0) {
            revert AltoBorrowMarketUnauthorized();
        }

        if (!_isSolvent(onBehalf, false)) {
            revert AltoBorrowMarketInsufficientUserCollateral();
        }

        emit RemoveCollateral(msg.sender, onBehalf, receiver, assets);

        return (assets);
    }

    /// @inheritdoc IMarketBase
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata data)
        external
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares) || receiver == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBorrowMarketUnauthorized();
        }

        _accrueInterest();

        uint256 openingFeeAssets;

        if (assets == 0) {
            // calculate opening fee from shares
            uint256 openingFeeShares = shares.multiplyWithPrecision(borrowOpeningFee);
            openingFeeAssets = openingFeeShares.convertToAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
            shares += openingFeeShares;

            assets = shares.convertToAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            // calculate opening fee from assets
            openingFeeAssets = assets.multiplyWithPrecision(borrowOpeningFee);
            assets += openingFeeAssets;

            shares = assets.convertToSharesUp(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets += assets.toUint128();
        totalBorrowed.shares += shares.toUint128();

        if (totalBorrowed.assets > totalSupply.assets) {
            revert AltoBorrowMarketInsufficientMarketLiquidity();
        }

        position[onBehalf].borrowShares += shares.toUint128();

        // send assets to the receiver minus the opening fee as now `assets` includes the opening fee
        uint256 assetsToSend = assets - openingFeeAssets;
        _sendBorrowToken(address(this), receiver, assetsToSend);

        uint256 feeSupplyShares;
        if (openingFeeAssets > 0) {
            feeSupplyShares = _applyBorrowOpeningFee(openingFeeAssets);
        }

        if (authorizedCallbacks[receiver] && data.length > 0) {
            IBorrowCallback(receiver).onBorrowCallback(assetsToSend, data);
        } else if (data.length > 0) {
            revert AltoBorrowMarketUnauthorized();
        }

        if (!_isSolvent(onBehalf, false)) {
            revert AltoBorrowMarketBorrowingTooMuch();
        }

        emit Borrow(msg.sender, onBehalf, receiver, assetsToSend, shares, openingFeeAssets, feeSupplyShares);

        return (assets, shares, openingFeeAssets);
    }

    /// @dev Adds opening fee to the fee recipient's supply position and to the market.
    /// @param openingFeeAssets The amount of opening fee to add.
    /// @return feeSupplyShares The amount of shares added to the fee recipient's supply position.
    /// @dev This function is virtual to allow for custom logic in the case of mint market.
    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal virtual returns (uint256) {
        // add opening fee to the fee recipient's supply position
        uint256 feeSupplyShares = openingFeeAssets.convertToSharesUp(totalSupply.assets, totalSupply.shares);
        totalSupply.shares += feeSupplyShares.toUint128();
        totalSupply.assets += openingFeeAssets.toUint128();
        position[feeRecipient].supplyShares += feeSupplyShares.toUint128();

        return feeSupplyShares;
    }

    /// @inheritdoc IMarketBase
    function repay(uint256 assets, uint256 shares, address onBehalf)
        external
        whenNotPaused
        returns (uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares) || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets -= assets.toUint128();
        totalBorrowed.shares -= shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);
        position[onBehalf].borrowShares -= shares.toUint128();

        emit Repay(msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function accrueInterest() external whenNotPaused {
        _accrueInterest();
    }

    /// @dev Accrues interest for the market.
    /// @dev If `irm` is set to zero address, this function does nothing.
    /// @dev This function is virtual to allow for custom logic in the case of mint market.
    function _accrueInterest() internal virtual {
        if (irm == address(0)) {
            return;
        }

        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalSupply.assets += interest.toUint128();
        totalBorrowed.assets += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    /// @dev Returns true if the user's position is solvent.
    /// @param _user The address of the user whose position is being checked
    /// @param _isLiquidation If true, checks if the position is solvent for liquidation.
    /// If false, checks if the position is solvent for normal operations. In other words,
    /// uses `maxLtv` instead of `liquidationConfiguration.maxLiquidationLtv` to make a decision.
    function _isSolvent(address _user, bool _isLiquidation) internal view returns (bool) {
        uint256 collateralPrice = IOracle(oracle).getPrice();
        uint256 collateralValue =
            uint256(position[_user].collateralAssets).divideWithRounding(collateralPrice, ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue =
            collateralValue.multiplyWithPrecision(_isLiquidation ? liquidationConfiguration.maxLiquidationLtv : maxLtv);
        uint256 borrowValue =
            uint256(position[_user].borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        if (_isLiquidation) {
            return borrowValue == 0 || maxBorrowValue > borrowValue;
        }

        return maxBorrowValue >= borrowValue;
    }

    /// @inheritdoc IMarketBase
    function liquidate(address borrower, bytes calldata data) external whenNotPaused returns (uint256, uint256) {
        _accrueInterest();

        // Check if the position is underwater
        if (_isSolvent(borrower, true)) {
            revert AltoBorrowMarketLiquidatingSolventPosition();
        }

        Position memory _position = position[borrower];
        LiquidationCalculation memory calc;

        // Initial calculations
        calc.collateralPrice = IOracle(oracle).getPrice();

        calc.positionCollateralValue =
            uint256(_position.collateralAssets).divideWithRounding(calc.collateralPrice, ORACLE_PRICE_PRECISION, false);
        calc.positionBorrowedAssets =
            uint256(_position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        calc.currentLtv = calc.positionBorrowedAssets.divideWithPrecisionUp(calc.positionCollateralValue);

        // calculate liquidation percentage - how far are we between LTV and LLTV from current LTV
        calc.liquidationPercentage = _calculateLiquidationPercentage(calc.currentLtv);

        if (
            liquidationConfiguration.isEnabledPriorityLiquidation
                && calc.currentLtv < liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        ) {
            if (!priorityLiquidators[msg.sender] && !liquidablePositions[borrower].tagged) {
                revert AltoBorrowMarketLiquidationUnauthorized();
            }

            // Skip grace period checks for priority liquidators
            if (!priorityLiquidators[msg.sender]) {
                uint256 gracePeriod = liquidablePositions[borrower].tagger == msg.sender
                    ? liquidationConfiguration.priorityLiquidationGracePeriod
                    : liquidationConfiguration.priorityLiquidationGracePeriod
                        + liquidationConfiguration.taggerLiquidationGracePeriod;

                if (block.timestamp - liquidablePositions[borrower].timestamp <= gracePeriod) {
                    revert AltoBorrowMarketLiquidationUnauthorized();
                }
            }
        }

        // apply above to calculate liquidation fee (priority liquidators don't get a bonus fee only base fee)
        calc.liquidationFee = (!priorityLiquidators[msg.sender] ? _calculateBonusFee(calc.liquidationPercentage) : 0)
            + liquidationConfiguration.liquidationBaseFee;

        // calculate new LTV - how much LTV are we aiming for after liquidation
        calc.newLtv = _calculateNewLtv(calc.liquidationPercentage);

        // Calculate fee in collateral
        calc.liquidatorBonusFee = uint256(_position.collateralAssets).multiplyWithPrecision(calc.liquidationFee);
        uint256 remainingCollateralAfterFee = _position.collateralAssets - calc.liquidatorBonusFee;
        calc.remainingCollateralAfterFeeInBorrowAssets =
            remainingCollateralAfterFee.divideWithRounding(calc.collateralPrice, ORACLE_PRICE_PRECISION, false);

        calc.collateralToSellInBorrowAssets = (
            calc.positionBorrowedAssets
                - calc.remainingCollateralAfterFeeInBorrowAssets.multiplyWithPrecision(calc.newLtv)
        ).divideWithPrecisionUp(MATH_PRECISION - calc.newLtv);
        calc.collateralToSellInBorrowAssets =
            Math.min(calc.collateralToSellInBorrowAssets, calc.remainingCollateralAfterFeeInBorrowAssets);
        calc.collateralToSellInBorrowAssets = Math.min(calc.collateralToSellInBorrowAssets, calc.positionBorrowedAssets);

        // Calculate final amounts
        uint256 totalCollateralToTake = calc.collateralToSellInBorrowAssets.divideWithRounding(
            ORACLE_PRICE_PRECISION, calc.collateralPrice, true
        ) + calc.liquidatorBonusFee;
        uint256 f_collateralAmount =
            totalCollateralToTake > _position.collateralAssets ? _position.collateralAssets : totalCollateralToTake;

        uint256 f_repayAmount = calc.collateralToSellInBorrowAssets > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : calc.collateralToSellInBorrowAssets;

        uint256 f_repayShares = f_repayAmount.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);

        // Ensure we don't try to repay more shares than the user has which can happen since we are using virtual shares
        // we check whether substracting 1e6 from the repay shares is still greater than the user's borrow shares
        // as other values are not valid.
        if (
            f_repayShares.toUint128() > _position.borrowShares
                && f_repayShares - AssetShareConversionMath.VIRTUAL_SHARES < _position.borrowShares
        ) {
            f_repayShares = uint256(_position.borrowShares);
        }

        // apply liquidation
        position[borrower].collateralAssets -= f_collateralAmount.toUint128();
        position[borrower].borrowShares -= f_repayShares.toUint128();

        totalBorrowed.shares -= f_repayShares.toUint128();
        totalBorrowed.assets =
            (totalBorrowed.assets > f_repayAmount ? totalBorrowed.assets - f_repayAmount : 0).toUint128();

        if (
            liquidationConfiguration.isEnabledPriorityLiquidation
                && calc.currentLtv < liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        ) {
            delete liquidablePositions[borrower];
        }

        Balance memory badDebt;
        if (position[borrower].collateralAssets == 0) {
            badDebt.shares = position[borrower].borrowShares;
            badDebt.assets = uint128(
                Math.min(
                    totalBorrowed.assets,
                    uint256(badDebt.shares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares)
                )
            );

            _applyLiquidationBadDebt(badDebt, borrower);
        }

        // transfer collateral and borrow tokens
        IERC20(collateralToken).safeTransfer(msg.sender, f_collateralAmount);

        if (data.length > 0) {
            ILiquidateCallback(msg.sender).onLiquidateCallback(f_collateralAmount, data);
        }

        _sendBorrowToken(msg.sender, address(this), f_repayAmount);

        emit Liquidation(
            borrower,
            collateralToken,
            borrowToken,
            msg.sender,
            f_collateralAmount,
            f_repayAmount,
            f_repayShares,
            badDebt.assets,
            badDebt.shares
        );

        return (f_collateralAmount, f_repayAmount);
    }

    /// @dev Calculates the liquidation percentage - how far are we between LTV and LLTV with position's current LTV.
    /// @param currentLtv The current LTV of the position to be liquidated.
    /// @return liquidationPercentage The liquidation percentage.
    function _calculateLiquidationPercentage(uint256 currentLtv) internal view returns (uint256) {
        if (currentLtv >= liquidationConfiguration.ltvForCompleteLiquidation) {
            return MATH_PRECISION;
        } else {
            return (currentLtv - liquidationConfiguration.maxLiquidationLtv).divideWithPrecisionUp(
                liquidationConfiguration.ltvForCompleteLiquidation - liquidationConfiguration.maxLiquidationLtv
            );
        }
    }

    /// @dev Calculates the bonus fee for the liquidation - used to incentivize fast liquidators.
    /// @param liquidationPercentage The liquidation percentage.
    /// @return bonusFee The bonus fee.
    function _calculateBonusFee(uint256 liquidationPercentage) internal view returns (uint256) {
        if (liquidationPercentage < MATH_PRECISION && liquidationConfiguration.dynamicBonusFeeDecaySteepness > 0) {
            int256 exponent = -int256(liquidationConfiguration.dynamicBonusFeeDecaySteepness * liquidationPercentage)
                / MATH_PRECISION_INT;
            return liquidationConfiguration.dynamicBonusFeeStart.multiplyWithPrecision(uint256(ExpLib.wExp(exponent)));
        } else {
            return 0;
        }
    }

    /// @dev Calculates the new LTV after liquidation - how much LTV are we aiming for after liquidation.
    /// @param liquidationPercentage The liquidation percentage.
    /// @return newLtv The new LTV.
    function _calculateNewLtv(uint256 liquidationPercentage) internal view returns (uint256) {
        uint256 liquidationPercentageAppliedPenalty = liquidationPercentage
            < liquidationConfiguration.minPenaltyPercentage
            ? liquidationConfiguration.minPenaltyPercentage
            : liquidationPercentage;

        return maxLtv.multiplyWithPrecision(MATH_PRECISION - liquidationPercentageAppliedPenalty);
    }

    /// @dev Applies the bad debt to the market.
    /// @param badDebt The bad debt to apply.
    /// @param borrower The address of the borrower whose position is being liquidated.
    /// @dev This function is virtual to allow for custom logic in the case of mint market.
    function _applyLiquidationBadDebt(Balance memory badDebt, address borrower) internal virtual {
        totalBorrowed.shares -= badDebt.shares;
        totalBorrowed.assets -= badDebt.assets;

        totalSupply.assets -= badDebt.assets;

        position[borrower].borrowShares = 0;
    }

    /// @dev Sends the borrow token from one address to another.
    /// @param from The address of the sender.
    /// @param to The address of the receiver.
    /// @param amount The amount of borrow token to send.
    /// @dev This function is virtual to allow for custom logic in the case of mint market.
    function _sendBorrowToken(address from, address to, uint256 amount) internal virtual {
        if (from == address(this)) {
            IERC20(borrowToken).safeTransfer(to, amount);
        } else {
            IERC20(borrowToken).safeTransferFrom(from, to, amount);
        }
    }

    /// @inheritdoc IMarketBase
    function setPriorityLiquidator(address liquidator, bool status) external onlyOwner {
        if (liquidator == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        priorityLiquidators[liquidator] = status;
        emit PriorityLiquidatorUpdated(liquidator, status);
    }

    /// @inheritdoc IMarketBase
    function tagLiquidablePosition(address user, address liquidator) external whenNotPaused {
        if (!liquidationConfiguration.isEnabledPriorityLiquidation) {
            revert AltoBorrowMarketPriorityLiquidationDisabled();
        }

        _accrueInterest();

        if (_isSolvent(user, true)) {
            revert AltoBorrowMarketLiquidatingSolventPosition();
        }
        if (priorityLiquidators[liquidator]) {
            revert AltoBorrowMarketLiquidationUnauthorized();
        }
        if (liquidablePositions[user].timestamp > 0) {
            if (liquidablePositions[user].timestamp + liquidationConfiguration.liquidationWindowTag >= block.timestamp)
            {
                revert AltoBorrowMarketLiquidationAlreadyTagged();
            }
        }
        liquidablePositions[user] = LiquidablePosition({tagged: true, tagger: liquidator, timestamp: block.timestamp});
        emit PositionTagged(user, liquidator, block.timestamp);
    }

    /// @dev Modifier to check if the market is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSED_MARKET]) {
            revert IPausable.IsPaused(PAUSED_MARKET);
        }
        _;
    }

    /// @dev Modifier to check if the market is not frozen.
    modifier whenNotFrozen() {
        if (paused[FROZEN_MARKET]) {
            revert IPausable.IsPaused(FROZEN_MARKET);
        }
        _;
    }

    /// @dev Checks if one of the inputs is zero and the other is not.
    function _onlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }
}
