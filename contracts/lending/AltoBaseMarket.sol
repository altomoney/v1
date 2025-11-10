// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {
    Balance,
    Position,
    LiquidationConfiguration,
    LiquidationCalculation,
    LiquidationCalculationResult,
    LiquidablePosition
} from "@alto/lending/interfaces/IMarket.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

import {ExpLib, MATH_PRECISION_INT} from "./libraries/ExpLib.sol";
import {Uint128Converter} from "./libraries/Uint128Converter.sol";

import {FixedPointMath, MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";
import {PAUSE_TYPE, FROZEN_TYPE} from "@alto/utils/Constants.sol";
import {IMarketStaticTypes, IMarketBase} from "@alto/lending/interfaces/IMarket.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {AssetShareConversionMath} from "@alto/lending/libraries/AssetShareConversionMath.sol";
import {
    IBorrowCallback,
    IRemoveCollateralCallback,
    ILiquidateCallback
} from "@alto/lending/interfaces/IMarketCallbacks.sol";

/// @title Alto Base Market
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Borrow Market
abstract contract AltoBaseMarket is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    IMarketStaticTypes,
    AuthUpgradeable,
    Pausable
{
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
    address public feeRecipient;

    /// upgrade gap (previous slot has 12 bytes left)
    uint256[33] private __gap_base;

    function __AltoBaseMarket_init(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) internal onlyInitializing {
        _validateLiquidationConfiguration(_liquidationConfiguration, _maxLtv, _feeRecipient);

        if (_borrowToken == address(0) || _collateralToken == address(0) || _oracle == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_maxLtv > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_feeRecipient == address(0) && _liquidationConfiguration.protocolFeePercentage > 0) {
            revert AltoBaseMarketInvalidInput();
        }

        borrowToken = _borrowToken;
        collateralToken = _collateralToken;

        irm = _irm;
        emit SetIrm(address(0), _irm);

        oracle = _oracle;
        emit SetOracle(address(0), _oracle);

        maxLtv = _maxLtv;
        emit SetMaxLtv(0, _maxLtv);

        liquidationConfiguration = _liquidationConfiguration;
        emit SetLiquidationConfiguration(
            LiquidationConfiguration({
                maxLiquidationLtv: 0,
                dynamicBonusFeeStart: 0,
                ltvForCompleteLiquidation: 0,
                dynamicBonusFeeDecaySteepness: 0,
                liquidationBaseFee: 0,
                minPenaltyPercentage: 0,
                protocolFeePercentage: 0,
                isEnabledPriorityLiquidation: false,
                disablePriorityLiquidationAbovePositionLtv: 0,
                priorityLiquidationGracePeriod: 0,
                taggerLiquidationGracePeriod: 0,
                liquidationWindowTag: 0
            }),
            _liquidationConfiguration
        );

        feeRecipient = _feeRecipient;
        emit SetFeeRecipient(address(0), _feeRecipient);

        if (irm != address(0)) {
            IIrm(irm).setMarket(address(this));
        }

        _setPauser(_owner, PAUSE_TYPE, true);
        _setPauser(_owner, FROZEN_TYPE, true);

        __Ownable_init(_owner);
        __Auth_init();
    }

    /// @inheritdoc IMarketBase
    function borrowOpeningFee() public view virtual returns (uint256);

    /// @inheritdoc IMarketBase
    function setIrm(address _irm) external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            _accrueInterest();
        }

        emit SetIrm(irm, _irm);
        irm = _irm;

        if (irm != address(0)) {
            IIrm(irm).setMarket(address(this));
        }
    }

    /// @inheritdoc IMarketBase
    function setOracle(address _oracle) external onlyOwner {
        if (_oracle == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetOracle(oracle, _oracle);
        oracle = _oracle;
    }

    /// @inheritdoc IMarketBase
    function setMaxLtv(uint256 _maxLtv) external onlyOwner {
        if (_maxLtv > MATH_PRECISION || _maxLtv > liquidationConfiguration.maxLiquidationLtv) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetMaxLtv(maxLtv, _maxLtv);
        maxLtv = _maxLtv;
    }

    /// @inheritdoc IMarketBase
    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration) external onlyOwner {
        _validateLiquidationConfiguration(_liquidationConfiguration, maxLtv, feeRecipient);

        emit SetLiquidationConfiguration(liquidationConfiguration, _liquidationConfiguration);
        liquidationConfiguration = _liquidationConfiguration;
    }

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

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _feeRecipient) external virtual onlyOwner {
        if (
            _feeRecipient == address(0)
                && (borrowOpeningFee() > 0 || liquidationConfiguration.protocolFeePercentage > 0)
        ) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IMarketBase
    function setAuthorizedCallback(address callback, bool value) external onlyOwner {
        if (callback == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        authorizedCallbacks[callback] = value;
        emit SetAuthorizedCallback(callback, value);
    }

    /// @inheritdoc IPausable
    function setPauser(address pauser, bytes32 pauseType, bool status)
        external
        override(IPausable, Pausable)
        onlyOwner
    {
        _setPauser(pauser, pauseType, status);
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
            revert AltoBaseMarketInvalidInput();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsUp(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.convertToSharesDown(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets += assets.toUint128();
        totalSupply.shares += shares.toUint128();

        position[onBehalf].supplyShares += shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);

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
            revert AltoBaseMarketInvalidInput();
        }
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBaseMarketUnauthorized();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsDown(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.convertToSharesUp(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets -= assets.toUint128();
        totalSupply.shares -= shares.toUint128();

        position[onBehalf].supplyShares -= shares.toUint128();

        _sendBorrowToken(address(this), receiver, assets);

        emit RemoveSupply(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function addCollateral(uint256 assets, address onBehalf) external whenNotPaused whenNotFrozen returns (uint256) {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        position[onBehalf].collateralAssets += assets.toUint128();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        emit AddCollateral(msg.sender, onBehalf, assets);

        return (assets);
    }

    /// @inheritdoc IMarketBase
    function removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        external
        whenNotPaused
        returns (uint256)
    {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBaseMarketUnauthorized();
        }

        _accrueInterest();

        position[onBehalf].collateralAssets -= assets.toUint128();

        IERC20(collateralToken).safeTransfer(receiver, assets);

        if (authorizedCallbacks[receiver] && swapParams.length > 0) {
            IRemoveCollateralCallback(receiver).onRemoveCollateralCallback(assets, onBehalf, swapParams);
        } else if (swapParams.length > 0) {
            revert AltoBaseMarketUnauthorized();
        }

        if (!_isSolvent(onBehalf, false)) {
            revert AltoBaseMarketInsufficientUserCollateral();
        }

        emit RemoveCollateral(msg.sender, onBehalf, receiver, assets);

        return (assets);
    }

    /// @inheritdoc IMarketBase
    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        external
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256, uint256)
    {
        if (!_onlyOneZero(assets, shares) || receiver == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }
        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBaseMarketUnauthorized();
        }

        _accrueInterest();

        uint256 openingFeeAssets;

        if (assets == 0) {
            // calculate opening fee from shares
            uint256 openingFeeShares = shares.multiplyWithPrecisionUp(borrowOpeningFee());
            openingFeeAssets = openingFeeShares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
            shares += openingFeeShares;

            assets = shares.convertToAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            // calculate opening fee from assets
            openingFeeAssets = assets.multiplyWithPrecisionUp(borrowOpeningFee());
            assets += openingFeeAssets;

            shares = assets.convertToSharesUp(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets += assets.toUint128();
        totalBorrowed.shares += shares.toUint128();

        if (totalBorrowed.assets > totalSupply.assets) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        position[onBehalf].borrowShares += shares.toUint128();

        // send assets to the receiver minus the opening fee as now `assets` includes the opening fee
        uint256 assetsToSend = assets - openingFeeAssets;
        _sendBorrowToken(address(this), receiver, assetsToSend);

        uint256 feeSupplyShares;
        if (openingFeeAssets > 0) {
            feeSupplyShares = _applyBorrowOpeningFee(openingFeeAssets);
        }

        if (authorizedCallbacks[receiver]) {
            if (swapParams.length == 0) {
                revert AltoBaseMarketInvalidInput();
            }
            IBorrowCallback(receiver).onBorrowCallback(assetsToSend, onBehalf, swapParams);
        } else if (swapParams.length > 0) {
            revert AltoBaseMarketUnauthorized();
        }

        if (!_isSolvent(onBehalf, false)) {
            revert AltoBaseMarketBorrowingTooMuch();
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
    function repay(uint256 assets, uint256 shares, address onBehalf) external whenNotPaused returns (uint256, uint256) {
        if (!_onlyOneZero(assets, shares) || onBehalf == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        _accrueInterest();

        if (assets == 0) {
            assets = shares.convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets -= assets.toUint128();
        totalBorrowed.shares -= shares.toUint128();

        position[onBehalf].borrowShares -= shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);

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
        uint256 collateralPrice = ILendingOracle(oracle).getPrice();
        uint256 collateralValue = uint256(position[_user].collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
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
    function liquidate(address borrower, bytes calldata data)
        external
        whenNotPaused
        returns (uint256, uint256, uint256)
    {
        _accrueInterest();

        // Check if the position is underwater
        if (_isSolvent(borrower, true)) {
            revert AltoBaseMarketLiquidatingSolventPosition();
        }

        Position memory _position = position[borrower];
        LiquidationCalculation memory calc;

        // Initial calculations
        calc.collateralPrice = ILendingOracle(oracle).getPrice();

        calc.positionCollateralValue = uint256(_position.collateralAssets)
            .divideWithRounding(calc.collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        calc.positionBorrowedAssets =
            uint256(_position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        calc.currentLtv = calc.positionBorrowedAssets.divideWithPrecisionUp(calc.positionCollateralValue);

        // calculate liquidation percentage - how far are we between LTV and LLTV from current LTV
        calc.liquidationPercentage = _calculateLiquidationPercentage(calc.currentLtv);

        if (
            liquidationConfiguration.isEnabledPriorityLiquidation
                && calc.currentLtv <= liquidationConfiguration.disablePriorityLiquidationAbovePositionLtv
        ) {
            if (!priorityLiquidators[msg.sender] && !liquidablePositions[borrower].tagged) {
                revert AltoBaseMarketLiquidationUnauthorized();
            }

            // Skip grace period checks for priority liquidators
            if (!priorityLiquidators[msg.sender]) {
                uint256 gracePeriod = liquidablePositions[borrower].tagger == msg.sender
                    ? liquidationConfiguration.priorityLiquidationGracePeriod
                    : liquidationConfiguration.priorityLiquidationGracePeriod
                        + liquidationConfiguration.taggerLiquidationGracePeriod;

                if (block.timestamp - liquidablePositions[borrower].timestamp <= gracePeriod) {
                    revert AltoBaseMarketLiquidationUnauthorized();
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
        calc.protocolFee = uint256(calc.liquidatorBonusFee)
            .divideWithRounding(liquidationConfiguration.protocolFeePercentage, MATH_PRECISION, true);
        uint256 remainingCollateralAfterFee = _position.collateralAssets - calc.liquidatorBonusFee;
        calc.remainingCollateralAfterFeeInBorrowAssets =
            remainingCollateralAfterFee.divideWithRounding(calc.collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);

        calc.collateralToSellInBorrowAssets = (calc.positionBorrowedAssets
                - calc.remainingCollateralAfterFeeInBorrowAssets.multiplyWithPrecision(calc.newLtv))
        .divideWithPrecisionUp(MATH_PRECISION - calc.newLtv);
        calc.collateralToSellInBorrowAssets =
            Math.min(calc.collateralToSellInBorrowAssets, calc.remainingCollateralAfterFeeInBorrowAssets);
        calc.collateralToSellInBorrowAssets = Math.min(calc.collateralToSellInBorrowAssets, calc.positionBorrowedAssets);

        // Calculate final amounts
        LiquidationCalculationResult memory result;
        uint256 totalCollateralToTake = calc.collateralToSellInBorrowAssets
            .divideWithRounding(LENDING_ORACLE_PRICE_PRECISION, calc.collateralPrice, true) + calc.liquidatorBonusFee;
        result.collateralAmount =
            totalCollateralToTake > _position.collateralAssets ? _position.collateralAssets : totalCollateralToTake;

        result.repayAmount = calc.collateralToSellInBorrowAssets > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : calc.collateralToSellInBorrowAssets;

        result.repayShares = result.repayAmount.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);

        // Ensure we don't try to repay more shares than the user has which can happen since we are using virtual shares
        if (result.repayShares.toUint128() > _position.borrowShares) {
            result.repayShares = uint256(_position.borrowShares);
        }

        // apply liquidation
        position[borrower].collateralAssets -= result.collateralAmount.toUint128();
        position[borrower].borrowShares -= result.repayShares.toUint128();

        totalBorrowed.shares -= result.repayShares.toUint128();
        totalBorrowed.assets =
            (totalBorrowed.assets > result.repayAmount ? totalBorrowed.assets - result.repayAmount : 0).toUint128();

        delete liquidablePositions[borrower];

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

        // apply protocol fee
        position[feeRecipient].collateralAssets += calc.protocolFee.toUint128();

        result.collateralAmountToSend = result.collateralAmount - calc.protocolFee;

        // transfer collateral and borrow tokens with applied protocol fee
        IERC20(collateralToken).safeTransfer(msg.sender, result.collateralAmountToSend);

        if (data.length > 0) {
            ILiquidateCallback(msg.sender).onLiquidateCallback(result.repayAmount, result.collateralAmountToSend, data);
        }

        _sendBorrowToken(msg.sender, address(this), result.repayAmount);

        emit Liquidation(
            borrower,
            collateralToken,
            borrowToken,
            msg.sender,
            result.collateralAmount,
            calc.protocolFee,
            calc.liquidatorBonusFee,
            result.repayAmount,
            result.repayShares,
            badDebt.assets,
            badDebt.shares
        );

        return (result.collateralAmount, result.repayAmount, calc.protocolFee);
    }

    /// @dev Calculates the liquidation percentage - how far are we between LTV and LLTV with position's current LTV.
    /// @param currentLtv The current LTV of the position to be liquidated.
    /// @return liquidationPercentage The liquidation percentage.
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

    /// @dev Calculates the bonus fee for the liquidation - used to incentivize fast liquidators.
    /// @param liquidationPercentage The liquidation percentage.
    /// @return bonusFee The bonus fee.
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
            revert AltoBaseMarketInvalidInput();
        }

        priorityLiquidators[liquidator] = status;
        emit PriorityLiquidatorUpdated(liquidator, status);
    }

    /// @inheritdoc IMarketBase
    function tagLiquidablePosition(address user, address liquidator) external whenNotPaused {
        if (!liquidationConfiguration.isEnabledPriorityLiquidation) {
            revert AltoBaseMarketPriorityLiquidationDisabled();
        }

        _accrueInterest();

        if (_isSolvent(user, true)) {
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

    /// @dev Checks if one of the inputs is zero and the other is not.
    function _onlyOneZero(uint256 x, uint256 y) internal pure returns (bool) {
        return (x == 0 && y != 0) || (x != 0 && y == 0);
    }

    /// @dev Modifier to check if the market is not paused.
    modifier whenNotPaused() {
        if (paused[PAUSE_TYPE]) {
            revert IPausable.IsPaused(PAUSE_TYPE);
        }
        _;
    }

    /// @dev Modifier to check if the market is not frozen.
    modifier whenNotFrozen() {
        if (paused[FROZEN_TYPE]) {
            revert IPausable.IsPaused(FROZEN_TYPE);
        }
        _;
    }

    function _onPause(bytes32 pauseType, bool _paused) internal override {
        if (pauseType == PAUSE_TYPE) {
            if (_paused) {
                _accrueInterest();
            } else {
                IIrm(irm).onMarketPause(_paused);
            }
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
