// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle, ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {
    Balance,
    Position,
    LiquidationConfiguration,
    LiquidationCalculation,
    LiquidablePosition
} from "./interfaces/IMarket.sol";
import {Auth} from "@alto/utils/Auth.sol";
import {IIrm} from "./interfaces/IIrm.sol";

import {ExpLib, MATH_PRECISION_INT} from "./libraries/ExpLib.sol";
import {FixedPointMath, MATH_PRECISION} from "./libraries/FixedPointMath.sol";
import {Utils} from "./libraries/Utils.sol";

import {PAUSED_MARKET, FROZEN_MARKET} from "@alto/utils/Constants.sol";
import {IMarketStaticTypes} from "./interfaces/IMarket.sol";
import {Pausable, IPausable} from "@alto/utils/Pausable.sol";
import {AssetShareConversionMath} from "./libraries/AssetShareConversionMath.sol";
import {IBorrowCallback, IRemoveCollateralCallback, ILiquidateCallback} from "./interfaces/IMarketCallbacks.sol";

contract AltoBorrowMarket is Auth, Pausable, IMarketStaticTypes {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Utils for uint256;

    using SafeERC20 for IERC20;

    address public borrowToken;
    address public collateralToken;

    Balance public totalSupply;
    Balance public totalBorrowed;

    mapping(address => Position) public position;

    mapping(address => bool) public authorizedCallbacks;

    mapping(address => bool) public priorityLiquidators;

    mapping(address => LiquidablePosition) public liquidablePositions;

    address public irm;

    address public oracle;

    uint256 public maxLtv;

    LiquidationConfiguration public liquidationConfiguration;

    uint256 public borrowOpeningFee;

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
        borrowToken = _borrowToken;
        collateralToken = _collateralToken;
        irm = _irm;
        oracle = _oracle;
        maxLtv = _maxLtv;
        liquidationConfiguration = _liquidationConfiguration;
        borrowOpeningFee = _borrowOpeningFee;
        feeRecipient = _feeRecipient;

        IIrm(irm).setMarket(address(this));
    }

    function setIrm(address _irm) external onlyOwner {
        _accrueInterest();
        irm = _irm;
        IIrm(irm).setMarket(address(this));
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function setMaxLtv(uint256 _maxLtv) external onlyOwner {
        maxLtv = _maxLtv;
    }

    function setLiquidationConfiguration(LiquidationConfiguration memory _liquidationConfiguration)
        external
        onlyOwner
    {
        liquidationConfiguration = _liquidationConfiguration;
    }

    function setBorrowOpeningFee(uint256 _borrowOpeningFee) external onlyOwner {
        borrowOpeningFee = _borrowOpeningFee;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function addSupply(uint256 assets, uint256 shares, address onBehalf)
        external
        virtual
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256)
    {
        if (!Utils.onlyOneZero(assets, shares) || onBehalf == address(0)) {
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

    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        virtual
        whenNotPaused
        returns (uint256, uint256)
    {
        if (!Utils.onlyOneZero(assets, shares) || receiver == address(0)) {
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

    function addCollateral(uint256 assets, address onBehalf) external whenNotPaused whenNotFrozen returns (uint256) {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        position[onBehalf].collateralAssets += assets.toUint128();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        emit AddCollateral(msg.sender, onBehalf, assets);

        return (assets);
    }

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

    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata data)
        external
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256, uint256)
    {
        if (!Utils.onlyOneZero(assets, shares) || receiver == address(0)) {
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

    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal virtual returns (uint256) {
        // add opening fee to the fee recipient's supply position
        uint256 feeSupplyShares = openingFeeAssets.convertToSharesDown(totalSupply.assets, totalSupply.shares);
        totalSupply.shares += feeSupplyShares.toUint128();
        totalSupply.assets += openingFeeAssets.toUint128();
        position[feeRecipient].supplyShares += feeSupplyShares.toUint128();

        return feeSupplyShares;
    }

    function repay(uint256 assets, uint256 shares, address onBehalf)
        external
        whenNotPaused
        returns (uint256, uint256)
    {
        if (!Utils.onlyOneZero(assets, shares) || onBehalf == address(0)) {
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

    function accrueInterest() external whenNotPaused {
        _accrueInterest();
    }

    function _accrueInterest() internal virtual {
        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalSupply.assets += interest.toUint128();
        totalBorrowed.assets += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    function _isSolvent(address _user, bool _isLiquidation) internal view returns (bool) {
        uint256 collateralPrice = IOracle(oracle).getPrice();
        uint256 collateralValue =
            uint256(position[_user].collateralAssets).divideWithRounding(collateralPrice, ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue =
            collateralValue.multiplyWithPrecision(_isLiquidation ? liquidationConfiguration.maxLiquidationLtv : maxLtv);
        uint256 borrowValue =
            uint256(position[_user].borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return _isLiquidation ? maxBorrowValue > borrowValue : maxBorrowValue >= borrowValue;
    }

    function _calculateLiquidationPercentage(uint256 currentLtv) internal view returns (uint256) {
        if (currentLtv >= liquidationConfiguration.ltvForCompleteLiquidation) {
            return MATH_PRECISION;
        } else {
            return (currentLtv - liquidationConfiguration.maxLiquidationLtv).divideWithPrecisionUp(
                liquidationConfiguration.ltvForCompleteLiquidation - liquidationConfiguration.maxLiquidationLtv
            );
        }
    }

    function _calculateBonusFee(uint256 liquidationPercentage) internal view returns (uint256) {
        if (liquidationPercentage < MATH_PRECISION) {
            int256 exponent = -int256(liquidationConfiguration.dynamicBonusFeeDecaySteepness * liquidationPercentage)
                / MATH_PRECISION_INT;
            return liquidationConfiguration.dynamicBonusFeeStart.multiplyWithPrecision(uint256(ExpLib.wExp(exponent)));
        } else {
            return 0;
        }
    }

    function _calculateNewLtv(uint256 liquidationPercentage) internal view returns (uint256) {
        uint256 liquidationPercentageAppliedPenalty = liquidationPercentage
            < liquidationConfiguration.minPenaltyPercentage
            ? liquidationConfiguration.minPenaltyPercentage
            : liquidationPercentage;

        return maxLtv.multiplyWithPrecision(MATH_PRECISION - liquidationPercentageAppliedPenalty);
    }

    /// @notice Liquidate a position
    /// @param borrower The address of the user to liquidate
    /// @return The result of the liquidation
    /// @dev The liquidator must be an external liquidator which tagged the position or any liquidator that waited for the grace period or a priority liquidator
    function liquidate(address borrower, bytes calldata data) external whenNotPaused returns (uint256, uint256) {
        _accrueInterest();

        // Check if the position is underwater
        if (_isSolvent(borrower, true)) {
            revert AltoBorrowMarketLiquidatingHealthyPosition();
        }

        if (!priorityLiquidators[msg.sender] && !liquidablePositions[borrower].tagged) {
            revert AltoBorrowMarketLiquidationUnauthorized();
        }

        if (
            !priorityLiquidators[msg.sender] && liquidablePositions[borrower].tagged
                && liquidablePositions[borrower].tagger == msg.sender
        ) {
            if (
                block.timestamp - liquidablePositions[borrower].timestamp
                    <= liquidationConfiguration.priorityLiquidationGracePeriod
            ) {
                revert AltoBorrowMarketLiquidationUnauthorized();
            }
        }
        if (
            !priorityLiquidators[msg.sender] && liquidablePositions[borrower].tagged
                && liquidablePositions[borrower].tagger != msg.sender
        ) {
            if (
                block.timestamp - liquidablePositions[borrower].timestamp
                    <= liquidationConfiguration.priorityLiquidationGracePeriod
                        + liquidationConfiguration.taggerLiquidationGracePeriod
            ) {
                revert AltoBorrowMarketLiquidationUnauthorized();
            }
        }

        Position memory _position = position[borrower];
        LiquidationCalculation memory calc;

        // Initial calculations
        calc.collateralPrice = IOracle(oracle).getPrice();

        calc.positionCollateralValue =
            uint256(_position.collateralAssets).divideWithRounding(calc.collateralPrice, ORACLE_PRICE_PRECISION, false);
        calc.positionBorrowedAssets =
            uint256(_position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        // calculate liquidation percentage - how far are we between LTV and LLTV from current LTV
        calc.liquidationPercentage = _calculateLiquidationPercentage(
            calc.positionBorrowedAssets.divideWithPrecisionUp(calc.positionCollateralValue)
        );

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

        uint256 collateralToSellInBorrowAssets = (
            calc.positionBorrowedAssets
                - calc.remainingCollateralAfterFeeInBorrowAssets.multiplyWithPrecision(calc.newLtv)
        ).divideWithPrecisionUp(MATH_PRECISION - calc.newLtv);
        collateralToSellInBorrowAssets =
            Math.min(collateralToSellInBorrowAssets, calc.remainingCollateralAfterFeeInBorrowAssets);
        collateralToSellInBorrowAssets = Math.min(collateralToSellInBorrowAssets, calc.positionBorrowedAssets);

        // Calculate final amounts
        uint256 totalCollateralToTake = collateralToSellInBorrowAssets.divideWithRounding(
            ORACLE_PRICE_PRECISION, calc.collateralPrice, true
        ) + calc.liquidatorBonusFee;
        uint256 f_collateralAmount =
            totalCollateralToTake > _position.collateralAssets ? _position.collateralAssets : totalCollateralToTake;

        uint256 f_repayAmount = collateralToSellInBorrowAssets > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : collateralToSellInBorrowAssets;

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

    function _applyLiquidationBadDebt(Balance memory badDebt, address borrower) internal virtual {
        totalBorrowed.shares -= badDebt.shares;
        totalBorrowed.assets -= badDebt.assets;

        totalSupply.assets -= badDebt.assets;

        position[borrower].borrowShares = 0;
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal virtual {
        if (from == address(this)) {
            IERC20(borrowToken).safeTransfer(to, amount);
        } else {
            IERC20(borrowToken).safeTransferFrom(from, to, amount);
        }
    }

    function setAuthorizedCallback(address callback, bool value) external onlyOwner {
        authorizedCallbacks[callback] = value;
    }

    /// @notice Set an address as a priority liquidator
    /// @param liquidator The address of the liquidator with priority liquidation rights
    function setPriorityLiquidator(address liquidator, bool status) external onlyOwner {
        priorityLiquidators[liquidator] = status;
        emit PriorityLiquidatorUpdated(liquidator, status);
    }

    /// @notice Tag a position for liquidation
    /// @param user The address of the user to tag
    /// @param liquidator The address of the liquidator to tag the position for
    /// @dev The external liquidator must NOT be a priority liquidator
    function tagLiquidablePosition(address user, address liquidator) external whenNotPaused {
        if (_isSolvent(user, true)) {
            revert AltoBorrowMarketLiquidatingHealthyPosition();
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

    modifier whenNotPaused() {
        if (paused[PAUSED_MARKET]) {
            revert IPausable.IsPaused(PAUSED_MARKET);
        }
        _;
    }

    modifier whenNotFrozen() {
        if (paused[FROZEN_MARKET]) {
            revert IPausable.IsPaused(FROZEN_MARKET);
        }
        _;
    }
}
