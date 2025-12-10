// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AltoOwnable2StepUpgradeable} from "@alto/utils/AltoOwnable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ILendingOracle, LENDING_ORACLE_PRICE_PRECISION} from "@alto/oracles/interfaces/IOracle.sol";

import {Balance, Position, BaseMarketInitParams, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {AuthUpgradeable} from "@alto/utils/AuthUpgradeable.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";

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
import {
    IAltoLiquidationEngine,
    LiquidationEngineResult,
    LiquidationEngineInput
} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";

/// @title Alto Base Market
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Borrow Market
abstract contract AltoBaseMarket is
    Initializable,
    UUPSUpgradeable,
    AltoOwnable2StepUpgradeable,
    IMarketStaticTypes,
    AuthUpgradeable,
    Pausable,
    ReentrancyGuardUpgradeable
{
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;
    using Uint128Converter for uint256;

    using SafeERC20 for IERC20;

    /// @inheritdoc IMarketBase
    MarketType public MARKET_TYPE;

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
    address public irm;

    /// @inheritdoc IMarketBase
    address public oracle;

    /// @inheritdoc IMarketBase
    uint256 public maxLtv;

    /// @inheritdoc IMarketBase
    address public feeRecipient;

    /// @inheritdoc IMarketBase
    address public liquidationEngine;

    /// upgrade gap (previous slot has 12 bytes left)
    uint256[35] private __gap_base;

    function __AltoBaseMarket_init(BaseMarketInitParams memory _initParams, MarketType _marketType)
        internal
        onlyInitializing
    {
        MARKET_TYPE = _marketType;

        if (
            _initParams.borrowToken == address(0) || _initParams.collateralToken == address(0)
                || _initParams.oracle == address(0) || _initParams.liquidationEngine == address(0)
        ) {
            revert AltoBaseMarketInvalidInput();
        }
        if (_initParams.maxLtv > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }

        borrowToken = _initParams.borrowToken;
        collateralToken = _initParams.collateralToken;

        liquidationEngine = _initParams.liquidationEngine;
        emit SetLiquidationEngine(address(0), _initParams.liquidationEngine);

        if (liquidationEngine != address(0)) {
            IAltoLiquidationEngine(liquidationEngine).setMarketOnce(address(this));
        }

        irm = _initParams.irm;
        emit SetIrm(address(0), _initParams.irm);

        oracle = _initParams.oracle;
        emit SetOracle(address(0), _initParams.oracle);

        maxLtv = _initParams.maxLtv;
        emit SetMaxLtv(0, _initParams.maxLtv);

        feeRecipient = _initParams.feeRecipient;
        emit SetFeeRecipient(address(0), _initParams.feeRecipient);

        if (irm != address(0)) {
            IIrm(irm).setMarket(address(this));
        }

        _setPauser(_initParams.owner, PAUSE_TYPE, true);
        _setPauser(_initParams.owner, FROZEN_TYPE, true);

        __Ownable_init(_initParams.owner);
        __Auth_init();
        __ReentrancyGuard_init();
    }

    /// @inheritdoc IMarketBase
    function borrowOpeningFee() public view virtual returns (uint256);

    /// @inheritdoc IMarketBase
    function setIrm(address _irm, bool _skipAccrueInterest) external onlyOwner {
        if (!paused[PAUSE_TYPE] && !_skipAccrueInterest) {
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
        uint256 maxLiquidationLtv = IAltoLiquidationEngine(liquidationEngine).minLltv();
        if (_maxLtv > MATH_PRECISION || _maxLtv > maxLiquidationLtv) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetMaxLtv(maxLtv, _maxLtv);
        maxLtv = _maxLtv;
    }

    /// @inheritdoc IMarketBase
    function setLiquidationEngine(address _liquidationEngine) external onlyOwner {
        if (_liquidationEngine == address(0)) {
            revert AltoBaseMarketInvalidInput();
        }

        emit SetLiquidationEngine(liquidationEngine, _liquidationEngine);
        liquidationEngine = _liquidationEngine;

        IAltoLiquidationEngine(liquidationEngine).setMarketOnce(address(this));
    }

    /// @inheritdoc IMarketBase
    function setFeeRecipient(address _feeRecipient) external virtual onlyOwner {
        uint256 protocolFeePercentage = IAltoLiquidationEngine(liquidationEngine).protocolFeePercentage();
        if (_feeRecipient == address(0) && (borrowOpeningFee() > 0 || protocolFeePercentage > 0)) {
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
        whenNotPaused
        whenNotFrozen
        returns (uint256, uint256)
    {
        return _addSupply(assets, shares, onBehalf);
    }

    /// @dev See `IMarketBase.addSupply`
    /// @dev This function is virtual to allow for custom logic.
    function _addSupply(uint256 assets, uint256 shares, address onBehalf) internal virtual returns (uint256, uint256) {
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
        whenNotPaused
        returns (uint256, uint256)
    {
        return _removeSupply(assets, shares, onBehalf, receiver);
    }

    /// @dev See `IMarketBase.removeSupply`
    /// @dev This function is virtual to allow for custom logic.
    function _removeSupply(uint256 assets, uint256 shares, address onBehalf, address receiver)
        internal
        virtual
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

        // Invariant to prevent donation of borrow assets and removing supply
        if (totalBorrowed.assets > totalSupply.assets) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        _sendBorrowToken(address(this), receiver, assets);

        emit RemoveSupply(msg.sender, onBehalf, receiver, assets, shares);

        return (assets, shares);
    }

    /// @inheritdoc IMarketBase
    function addCollateral(uint256 assets, address onBehalf) external whenNotPaused whenNotFrozen returns (uint256) {
        return _addCollateral(assets, onBehalf);
    }

    /// @dev See `IMarketBase.addCollateral`
    /// @dev This function is virtual to allow for custom logic.
    function _addCollateral(uint256 assets, address onBehalf) internal virtual returns (uint256) {
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
        nonReentrant
        returns (uint256)
    {
        return _removeCollateral(assets, onBehalf, receiver, swapParams);
    }

    /// @dev See `IMarketBase.removeCollateral`
    /// @dev This function is virtual to allow for custom logic.
    function _removeCollateral(uint256 assets, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        virtual
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

        if (!_isSolvent(onBehalf)) {
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
        nonReentrant
        returns (uint256, uint256, uint256)
    {
        return _borrow(assets, shares, onBehalf, receiver, swapParams);
    }

    /// @dev See `IMarketBase.borrow`
    /// @dev This function is virtual to allow for custom logic.
    function _borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        virtual
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

        if (!_isSolvent(onBehalf)) {
            revert AltoBaseMarketBorrowingTooMuch();
        }

        emit Borrow(msg.sender, onBehalf, receiver, assetsToSend, shares, openingFeeAssets, feeSupplyShares);

        return (assets, shares, openingFeeAssets);
    }

    /// @dev Adds opening fee to the fee recipient's supply position and to the market.
    /// @param openingFeeAssets The amount of opening fee to add.
    /// @return feeSupplyShares The amount of shares added to the fee recipient's supply position.
    /// @dev This function is virtual to allow for custom logic
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
        return _repay(assets, shares, onBehalf);
    }

    /// @dev See `IMarketBase.repay`
    /// @dev This function is virtual to allow for custom logic.
    function _repay(uint256 assets, uint256 shares, address onBehalf) internal virtual returns (uint256, uint256) {
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
    /// @dev This function is virtual to allow for custom logic.
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
    function _isSolvent(address _user) internal view returns (bool) {
        uint256 collateralPrice = ILendingOracle(oracle).getPrice();
        uint256 collateralValue = uint256(position[_user].collateralAssets)
            .divideWithRounding(collateralPrice, LENDING_ORACLE_PRICE_PRECISION, false);
        uint256 maxBorrowValue = collateralValue.multiplyWithPrecision(maxLtv);
        uint256 borrowValue =
            uint256(position[_user].borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares);

        return maxBorrowValue >= borrowValue;
    }

    /// @inheritdoc IMarketBase
    function liquidate(address borrower, bytes calldata callbackData, bytes calldata liquidationData)
        external
        whenNotPaused
        nonReentrant
        returns (uint256, uint256, uint256)
    {
        return _liquidate(borrower, callbackData, liquidationData);
    }

    /// @dev Liquidates a position.
    /// @param borrower The address of the borrower being liquidated.
    /// @param callbackData Additional data for the liquidator contract.
    /// @param liquidationData Additional data for the liquidation engine.
    /// @return The amount of collateral received.
    /// @return The amount of assets repaid.
    /// @return The amount of protocol fee paid.
    function _liquidate(address borrower, bytes calldata callbackData, bytes calldata liquidationData)
        internal
        virtual
        returns (uint256, uint256, uint256)
    {
        _accrueInterest();

        LiquidationEngineResult memory result = IAltoLiquidationEngine(liquidationEngine)
            .prepareLiquidation(
                LiquidationEngineInput({
                    borrower: borrower,
                    liquidator: msg.sender,
                    totalSupply: totalSupply,
                    totalBorrowed: totalBorrowed,
                    position: position[borrower],
                    maxLtv: maxLtv,
                    collateralPrice: ILendingOracle(oracle).getPrice(),
                    liquidationData: liquidationData
                })
            );
        // apply liquidation
        position[borrower].collateralAssets -= result.seizedCollateralAssets.toUint128();
        position[borrower].borrowShares -= result.repaidBorrowShares.toUint128();

        totalBorrowed.shares -= result.repaidBorrowShares.toUint128();
        totalBorrowed.assets = (totalBorrowed.assets > result.repaidBorrowAmount
                ? totalBorrowed.assets - result.repaidBorrowAmount
                : 0)
        .toUint128();

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
        position[feeRecipient].collateralAssets += result.protocolSeizedCollateralFee.toUint128();

        uint256 collateralAmountToSend = result.seizedCollateralAssets - result.protocolSeizedCollateralFee;

        // transfer collateral and borrow tokens with applied protocol fee
        IERC20(collateralToken).safeTransfer(msg.sender, collateralAmountToSend);

        if (callbackData.length > 0) {
            ILiquidateCallback(msg.sender)
                .onLiquidateCallback(result.repaidBorrowAmount, collateralAmountToSend, callbackData);
        }

        _sendBorrowToken(msg.sender, address(this), result.repaidBorrowAmount);

        emit Liquidation(
            borrower,
            msg.sender,
            result.seizedCollateralAssets,
            result.protocolSeizedCollateralFee,
            result.repaidBorrowAmount,
            result.repaidBorrowShares,
            badDebt.assets,
            badDebt.shares
        );

        return (result.seizedCollateralAssets, result.repaidBorrowAmount, result.protocolSeizedCollateralFee);
    }

    /// @inheritdoc IMarketBase
    function governanceLiquidate(address borrower) external onlyOwner nonReentrant returns (uint256, uint256) {
        _accrueInterest();

        Position memory _position = position[borrower];

        uint256 collateralAmount = _position.collateralAssets;

        uint256 badDebtAmount = Math.min(
            uint256(_position.borrowShares).convertToAssetsUp(totalBorrowed.assets, totalBorrowed.shares),
            totalBorrowed.assets
        );
        uint128 badDebtShares = position[borrower].borrowShares;

        _applyLiquidationBadDebt(Balance({shares: badDebtShares, assets: badDebtAmount.toUint128()}), borrower);

        position[borrower].collateralAssets = 0;

        if (collateralAmount > 0) {
            IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
        }

        emit GovernanceLiquidation(borrower, msg.sender, collateralAmount, badDebtAmount, badDebtShares);

        return (collateralAmount, badDebtAmount);
    }

    /// @dev Applies the bad debt to the market.
    /// @param badDebt The bad debt to apply.
    /// @param borrower The address of the borrower whose position is being liquidated.
    /// @dev This function is virtual to allow for custom logic.
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
    /// @dev This function is virtual to allow for custom logic.
    function _sendBorrowToken(address from, address to, uint256 amount) internal virtual {
        if (from == address(this)) {
            IERC20(borrowToken).safeTransfer(to, amount);
        } else {
            IERC20(borrowToken).safeTransferFrom(from, to, amount);
        }
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
