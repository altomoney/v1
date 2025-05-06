// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracle, ORACLE_PRICE_PRECISION} from "./interfaces/IOracle.sol";
import {
    Balance,
    Position,
    LiquidationConfiguration,
    LiquidationResult,
    LiquidationCalculation
} from "./interfaces/IMarket.sol";
import {Auth} from "tap-utils/utils/Auth.sol";
import {IIrm} from "./interfaces/IIrm.sol";

import {ExpLib, WAD_INT} from "./libraries/ExpLib.sol";

import {MathLib, WAD} from "@morpho-blue/libraries/MathLib.sol";
import {SharesMathLib} from "@morpho-blue/libraries/SharesMathLib.sol";
import {UtilsLib} from "@morpho-blue/libraries/UtilsLib.sol";
import {DOMAIN_TYPEHASH} from "tap-utils/utils/Constants.sol";
import {IMarkeStaticTypes} from "./interfaces/IMarket.sol";

contract AltoBorrowMarket is Ownable, Auth, IMarkeStaticTypes {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;
    using SafeERC20 for IERC20;

    bytes32 public immutable DOMAIN_SEPARATOR;

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
        DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
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
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterest();

        if (assets == 0) {
            assets = shares.toAssetsUp(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.toSharesDown(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets += assets.toUint128();
        totalSupply.shares += shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);
        position[onBehalf].supplyShares += shares.toUint128();

        emit EventsLib.AddSupply(msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }

    function removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        virtual
        returns (uint256, uint256)
    {
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest();

        if (assets == 0) {
            assets = shares.toAssetsDown(totalSupply.assets, totalSupply.shares);
        } else {
            shares = assets.toSharesUp(totalSupply.assets, totalSupply.shares);
        }

        totalSupply.assets -= assets.toUint128();
        totalSupply.shares -= shares.toUint128();

        _sendBorrowToken(address(this), receiver, assets);
        position[onBehalf].supplyShares -= shares.toUint128();

        emit EventsLib.RemoveSupply(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    function addCollateral(uint256 assets, address onBehalf) external returns (uint256) {
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        position[onBehalf].collateralAssets += assets.toUint128();

        IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), assets);

        emit EventsLib.AddCollateral(msg.sender, onBehalf, assets);

        return (assets);
    }

    function removeCollateral(uint256 assets, address onBehalf, address receiver) external returns (uint256) {
        require(assets != 0, ErrorsLib.ZERO_ASSETS);
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest();

        position[onBehalf].collateralAssets -= assets.toUint128();

        require(_isSolvent(onBehalf, false), ErrorsLib.INSUFFICIENT_COLLATERAL);
        IERC20(collateralToken).safeTransfer(receiver, assets);

        emit EventsLib.RemoveCollateral(msg.sender, onBehalf, receiver, assets);

        return (assets);
    }

    function borrow(uint256 assets, uint256 shares, address onBehalf, address receiver)
        external
        returns (uint256, uint256)
    {
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(receiver != address(0), ErrorsLib.ZERO_ADDRESS);
        require(_isSenderAuthorized(onBehalf), ErrorsLib.UNAUTHORIZED);

        _accrueInterest();

        if (assets == 0) {
            assets = shares.toAssetsDown(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.toSharesUp(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets += assets.toUint128();
        totalBorrowed.shares += shares.toUint128();
        require(totalBorrowed.assets <= totalSupply.assets, ErrorsLib.INSUFFICIENT_LIQUIDITY);

        position[onBehalf].borrowShares += shares.toUint128();
        require(_isSolvent(onBehalf, false), ErrorsLib.INSUFFICIENT_COLLATERAL);
        _sendBorrowToken(address(this), receiver, assets);

        emit EventsLib.Borrow(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    function repay(uint256 assets, uint256 shares, address onBehalf) external returns (uint256, uint256) {
        require(UtilsLib.exactlyOneZero(assets, shares), ErrorsLib.INCONSISTENT_INPUT);
        require(onBehalf != address(0), ErrorsLib.ZERO_ADDRESS);

        _accrueInterest();

        if (assets == 0) {
            assets = shares.toAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        } else {
            shares = assets.toSharesDown(totalBorrowed.assets, totalBorrowed.shares);
        }

        totalBorrowed.assets -= assets.toUint128();
        totalBorrowed.shares -= shares.toUint128();

        _sendBorrowToken(msg.sender, address(this), assets);
        position[onBehalf].borrowShares -= shares.toUint128();

        emit EventsLib.Repay(msg.sender, onBehalf, assets, shares);

        return (assets, shares);
    }

    function accrueInterest() external {
        _accrueInterest();
    }

    function _accrueInterest() internal virtual {
        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalSupply.assets += interest.toUint128();
        totalBorrowed.assets += interest.toUint128();

        emit EventsLib.AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    function _isSolvent(address _user, bool _isLiquidation) internal view returns (bool) {
        uint256 collateralPrice = IOracle(oracle).price();
        uint256 collateralValue =
            uint256(position[_user].collateralAssets).mulDivDown(collateralPrice, ORACLE_PRICE_PRECISION);
        uint256 maxBorrowValue =
            collateralValue.wMulDown(_isLiquidation ? liquidationConfiguration.maxLiquidationLtv : maxLtv);
        uint256 borrowValue =
            uint256(position[_user].borrowShares).toAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return _isLiquidation ? maxBorrowValue > borrowValue : maxBorrowValue >= borrowValue;
    }

    function _calculateLiquidationPercentage(uint256 currentLtv) internal view returns (uint256) {
        if (currentLtv >= liquidationConfiguration.ltvForCompleteLiquidation) {
            return WAD;
        } else {
            return (currentLtv - liquidationConfiguration.maxLiquidationLtv).wDivUp(
                liquidationConfiguration.ltvForCompleteLiquidation - liquidationConfiguration.maxLiquidationLtv
            );
        }
    }

    function _calculateBonusFee(uint256 liquidationPercentage) internal view returns (uint256) {
        if (liquidationPercentage < WAD) {
            int256 exponent =
                -int256(liquidationConfiguration.dynamicBonusFeeDecaySteepness * liquidationPercentage) / WAD_INT;
            return liquidationConfiguration.dynamicBonusFeeStart.wMulDown(uint256(ExpLib.wExp(exponent)));
        } else {
            return 0;
        }
    }

    function _calculateNewLtv(uint256 liquidationPercentage) internal view returns (uint256) {
        uint256 liquidationPercentageAppliedPenalty = liquidationPercentage
            < liquidationConfiguration.minPenaltyPercentage
            ? liquidationConfiguration.minPenaltyPercentage
            : liquidationPercentage;

        return maxLtv.wMulDown(WAD - liquidationPercentageAppliedPenalty);
    }

    function liquidate(address borrower) external returns (LiquidationResult memory) {
        _accrueInterest();

        // Check if the position is underwater
        require(!_isSolvent(borrower, true), ErrorsLib.HEALTHY_POSITION);

        Position memory _position = position[borrower];
        LiquidationCalculation memory calc;

        // Initial calculations
        calc.collateralPrice = IOracle(oracle).price();
        calc.positionCollateralValue =
            uint256(_position.collateralAssets).mulDivDown(calc.collateralPrice, ORACLE_PRICE_PRECISION);
        calc.positionBorrowedAssets =
            uint256(_position.borrowShares).toAssetsUp(totalBorrowed.assets, totalBorrowed.shares);
        calc.currentLtv = calc.positionBorrowedAssets.wDivUp(calc.positionCollateralValue);

        calc.liquidationPercentage = _calculateLiquidationPercentage(calc.currentLtv);
        calc.liquidationFee =
            _calculateBonusFee(calc.liquidationPercentage) + liquidationConfiguration.liquidationBaseFee;
        calc.newLtv = _calculateNewLtv(calc.liquidationPercentage);

        // Calculate collateral amounts
        calc.liquidatorBonusFee = uint256(_position.collateralAssets).wMulDown(calc.liquidationFee);
        uint256 remainingCollateral = _position.collateralAssets - calc.liquidatorBonusFee;
        calc.remainingCollateralValue = remainingCollateral.mulDivDown(calc.collateralPrice, ORACLE_PRICE_PRECISION);

        uint256 _collateralToSell = calc.remainingCollateralValue.wMulDown(calc.newLtv);
        uint256 collateralToSell =
            _collateralToSell > calc.positionBorrowedAssets ? calc.positionBorrowedAssets : _collateralToSell;

        // Calculate final amounts
        uint256 collateralToSellInBorrowAssets =
            (calc.positionBorrowedAssets - collateralToSell).wDivUp(WAD - calc.newLtv);

        calc.collateralToSell = collateralToSellInBorrowAssets.mulDivUp(ORACLE_PRICE_PRECISION, calc.collateralPrice);
        uint256 totalCollateralToTake = calc.collateralToSell + calc.liquidatorBonusFee;
        uint256 collateralAmount =
            totalCollateralToTake > _position.collateralAssets ? _position.collateralAssets : totalCollateralToTake;

        calc.expectedRepayAmount = calc.collateralToSell.mulDivUp(calc.collateralPrice, ORACLE_PRICE_PRECISION);
        calc.expectedRepayAmount = calc.expectedRepayAmount > calc.positionBorrowedAssets
            ? calc.positionBorrowedAssets
            : calc.expectedRepayAmount;

        uint256 repayShares = calc.expectedRepayAmount.toSharesDown(totalBorrowed.assets, totalBorrowed.shares);

        // Ensure we don't try to repay more shares than the user has which can happen since we are using virtual shares
        // we check whether substracting 1e6 from the repay shares is still greater than the user's borrow shares
        // as other values are not valid.
        if (
            repayShares.toUint128() > _position.borrowShares
                && repayShares - SharesMathLib.VIRTUAL_SHARES < _position.borrowShares
        ) {
            repayShares = uint256(_position.borrowShares);
        }

        // apply liquidation
        position[borrower].collateralAssets -= collateralAmount.toUint128();
        position[borrower].borrowShares -= repayShares.toUint128();

        totalBorrowed.shares -= repayShares.toUint128();
        totalBorrowed.assets = UtilsLib.zeroFloorSub(totalBorrowed.assets, calc.expectedRepayAmount).toUint128();

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

    function _getDomainSeparator() internal view override returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }
}
