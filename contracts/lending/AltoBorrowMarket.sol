// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOracle, ORACLE_PRICE_PRECISION} from "./interfaces/IOracle.sol";
import {
    Balance,
    Position,
    LiquidationConfiguration,
    LiquidationResult,
    LiquidationCalculation,
    IMarket
} from "./interfaces/IMarket.sol";
import {Auth} from "tap-utils/utils/Auth.sol";
import {IIrm} from "./interfaces/IIrm.sol";

import {ExpLib, MATH_PRECISION_INT} from "./libraries/ExpLib.sol";
import {AssetShareConversionMath} from "./libraries/AssetShareConversionMath.sol";
import {FixedPointMath, MATH_PRECISION} from "./libraries/FixedPointMath.sol";
import {Utils} from "./libraries/Utils.sol";
import {IMarkeStaticTypes} from "./interfaces/IMarket.sol";

contract AltoBorrowMarket is Ownable, Auth, IMarkeStaticTypes {
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Utils for uint256;

    using SafeERC20 for IERC20;

    address public borrowToken;
    address public collateralToken;

    Balance public totalSupply;
    Balance public totalBorrowed;

    mapping(address => Position) public position;

    address public irm;

    address public oracle;

    uint256 public maxLtv;

    LiquidationConfiguration public liquidationConfiguration;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        LiquidationConfiguration memory _liquidationConfiguration
    ) {
        borrowToken = _borrowToken;
        collateralToken = _collateralToken;
        irm = _irm;
        oracle = _oracle;
        maxLtv = _maxLtv;
        liquidationConfiguration = _liquidationConfiguration;

        _transferOwnership(_owner);
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

    function addSupply(uint256 assets, uint256 shares, address onBehalf) external virtual returns (uint256, uint256) {
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

    function addCollateral(uint256 assets, address onBehalf) external returns (uint256) {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        position[onBehalf].collateralAssets += assets.toUint128();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        emit AddCollateral(msg.sender, onBehalf, assets);

        return (assets);
    }

    function removeCollateral(uint256 assets, address onBehalf, address receiver) external returns (uint256) {
        if (assets == 0 || onBehalf == address(0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (!_isSenderAuthorized(onBehalf)) {
            revert AltoBorrowMarketUnauthorized();
        }

        _accrueInterest();

        position[onBehalf].collateralAssets -= assets.toUint128();

        if (!_isSolvent(onBehalf, false)) {
            revert AltoBorrowMarketInsufficientUserCollateral();
        }

        IERC20(collateralToken).safeTransfer(receiver, assets);

        emit RemoveCollateral(msg.sender, onBehalf, receiver, assets);

        return (assets);
    }

    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
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
            assets = shares.convertToAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.convertToSharesUp(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets += assets.toUint128();
        totalBorrowed.shares += shares.toUint128();

        if (totalBorrowed.assets > totalSupply.assets) {
            revert AltoBorrowMarketInsufficientMarketLiquidity();
        }

        position[onBehalf].borrowShares += shares.toUint128();
        if (!_isSolvent(onBehalf, false)) {
            revert AltoBorrowMarketBorrowingTooMuch();
        }
        _sendBorrowToken(address(this), receiver, assets);

        emit Borrow(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256) {
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

    function accrueInterest() external {
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

    function liquidate(address borrower) external returns (LiquidationResult memory) {
        _accrueInterest();

        // Check if the position is underwater
        if (_isSolvent(borrower, true)) {
            revert AltoBorrowMarketLiquidatingHealthyPosition();
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

        calc.liquidationPercentage = _calculateLiquidationPercentage(calc.currentLtv);
        calc.liquidationFee =
            _calculateBonusFee(calc.liquidationPercentage) + liquidationConfiguration.liquidationBaseFee;
        calc.newLtv = _calculateNewLtv(calc.liquidationPercentage);

        // Calculate collateral amounts
        calc.liquidatorBonusFee = uint256(_position.collateralAssets).multiplyWithPrecision(calc.liquidationFee);
        uint256 remainingCollateral = _position.collateralAssets - calc.liquidatorBonusFee;
        calc.remainingCollateralValue =
            remainingCollateral.divideWithRounding(calc.collateralPrice, ORACLE_PRICE_PRECISION, false);

        uint256 _collateralToSell = calc.remainingCollateralValue.multiplyWithPrecision(calc.newLtv);
        uint256 collateralToSell =
            _collateralToSell > calc.positionBorrowedAssets ? calc.positionBorrowedAssets : _collateralToSell;

        // Calculate final amounts
        uint256 collateralToSellInBorrowAssets =
            (calc.positionBorrowedAssets - collateralToSell).divideWithPrecisionUp(MATH_PRECISION - calc.newLtv);

        calc.collateralToSell =
            collateralToSellInBorrowAssets.divideWithRounding(ORACLE_PRICE_PRECISION, calc.collateralPrice, true);
        uint256 totalCollateralToTake = calc.collateralToSell + calc.liquidatorBonusFee;
        uint256 collateralAmount =
            totalCollateralToTake > _position.collateralAssets ? _position.collateralAssets : totalCollateralToTake;

        calc.expectedRepayAmount =
            calc.collateralToSell.divideWithRounding(calc.collateralPrice, ORACLE_PRICE_PRECISION, true);
        calc.expectedRepayAmount = calc.expectedRepayAmount > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : calc.expectedRepayAmount;

        uint256 repayShares = calc.expectedRepayAmount.convertToSharesDown(totalBorrowed.assets, totalBorrowed.shares);

        // Ensure we don't try to repay more shares than the user has which can happen since we are using virtual shares
        // we check whether substracting 1e6 from the repay shares is still greater than the user's borrow shares
        // as other values are not valid.
        if (
            repayShares.toUint128() > _position.borrowShares
                && repayShares - AssetShareConversionMath.VIRTUAL_SHARES < _position.borrowShares
        ) {
            repayShares = uint256(_position.borrowShares);
        }

        // apply liquidation
        position[borrower].collateralAssets -= collateralAmount.toUint128();
        position[borrower].borrowShares -= repayShares.toUint128();

        totalBorrowed.shares -= repayShares.toUint128();
        totalBorrowed.assets = (
            totalBorrowed.assets > calc.expectedRepayAmount ? totalBorrowed.assets - calc.expectedRepayAmount : 0
        ).toUint128();

        // TODO: handle bad debt

        // transfer collateral and borrow tokens
        IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
        // TODO: add a callback for the liqduidator to process received collateral and generate repay tokens
        //IERC20(borrowToken).safeTransferFrom(msg.sender, address(this), calc.expectedRepayAmount);
        _sendBorrowToken(msg.sender, address(this), calc.expectedRepayAmount);

        return LiquidationResult({
            currentLtv: calc.currentLtv,
            newLtv: calc.newLtv,
            optimalRepayAmount: calc.expectedRepayAmount,
            collateralAmount: collateralAmount
        });
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal virtual {
        if (from == address(this)) {
            IERC20(borrowToken).safeTransfer(to, amount);
        } else {
            IERC20(borrowToken).safeTransferFrom(from, to, amount);
        }
    }
}
