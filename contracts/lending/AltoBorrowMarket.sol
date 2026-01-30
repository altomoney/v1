// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "./AltoBaseMarket.sol";
import {BorrowMarketInitParams, MarketType} from "./interfaces/IMarket.sol";
import {MATH_PRECISION, FixedPointMath} from "@alto/utils/FixedPointMath.sol";
import {IIrm} from "./interfaces/IIrm.sol";
import {Uint128Converter} from "./libraries/Uint128Converter.sol";
import {AssetShareConversionMath} from "./libraries/AssetShareConversionMath.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {IAltoLiquidationEngine} from "./interfaces/IAltoLiquidationEngine.sol";

/// @title Alto Borrow Market
/// @author GPM
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Borrow Market
contract AltoBorrowMarket is AltoBaseMarket {
    using Uint128Converter for uint256;
    using FixedPointMath for uint256;
    using AssetShareConversionMath for uint256;

    /// @notice Thrown when the input is invalid
    error AltoBorrowMarketInvalidInput();

    /// @notice Thrown when the supply cap is exceeded
    error AltoBorrowMarketSupplyCapExceeded();

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    /// @notice Emitted when the supply cap is set
    /// @param oldSupplyCapAssets The old supply cap assets
    /// @param newSupplyCapAssets The new supply cap assets
    event SetSupplyCap(uint128 oldSupplyCapAssets, uint128 newSupplyCapAssets);

    /// @notice Emitted when the interest fee is set
    /// @param oldInterestFee The old interest fee
    /// @param newInterestFee The new interest fee
    event SetInterestFee(uint256 oldInterestFee, uint256 newInterestFee);

    /// @notice Emitted when interest fee is accrued
    /// @param recipient The recipient of the interest fee
    /// @param interest The amount of interest accrued
    /// @param feeShares The amount of fee shares accrued
    event InterestFeeAccrued(address indexed recipient, uint256 interest, uint256 feeShares);

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @notice The maximum amount of assets that can be supplied to the market
    uint128 public supplyCapAssets;

    /// @notice The interest fee in MATH_PRECISION charged on accrued interest
    /// @dev For borrow market we would be mixing borrow opening fee accumulated shares with shares accumulated from interest
    /// and that's totally fine and this would be our limitation.
    /// If we'd still want to be so precise and split borrow opening fees and interest
    /// we can still use offchain indexer to get the event data.
    uint256 public interestFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(BorrowMarketInitParams memory _initParams) public initializer {
        __AltoBaseMarket_init(_initParams.baseMarketInitParams, MarketType.BORROW);

        if (_initParams.initialBorrowOpeningFee > MATH_PRECISION || _initParams.initialInterestFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (
            _initParams.baseMarketInitParams.feeRecipient == address(0)
                && (_initParams.initialBorrowOpeningFee > 0 || _initParams.initialInterestFee > 0)
        ) {
            revert AltoBorrowMarketInvalidInput();
        }

        interestFee = _initParams.initialInterestFee;
        emit SetInterestFee(0, _initParams.initialInterestFee);

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);

        supplyCapAssets = _initParams.supplyCapAssets;
        emit SetSupplyCap(0, _initParams.supplyCapAssets);
    }

    /// @notice Getter of the borrow opening fee
    /// @return The borrow opening fee
    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function _addSupply(uint256 assets, uint256 shares, address onBehalf) internal override returns (uint256, uint256) {
        (uint256 addedAssets, uint256 addedShares) = super._addSupply(assets, shares, onBehalf);
        if (supplyCapAssets != 0 && totalSupply.assets > supplyCapAssets) {
            revert AltoBorrowMarketSupplyCapExceeded();
        }
        return (addedAssets, addedShares);
    }

    /// @dev Accrues interest for the market and applies the interest fee to the fee recipient.
    function _accrueInterest() internal override {
        if (irm == address(0)) {
            return;
        }

        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalSupply.assets += interest.toUint128();
        totalBorrowed.assets += interest.toUint128();

        uint256 feeShares;
        if (interestFee != 0) {
            uint256 feeBorrowAssets = interest.multiplyWithPrecision(interestFee);

            feeShares = feeBorrowAssets.convertToSharesDown(totalSupply.assets - feeBorrowAssets, totalSupply.shares);
            position[feeRecipient].supplyShares += feeShares.toUint128();
            totalSupply.shares += feeShares.toUint128();

            emit InterestFeeAccrued(feeRecipient, interest, feeShares);
        }

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    /// @notice Setter of the borrow opening fee
    /// @param _newBorrowOpeningFee The new borrow opening fee
    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _newBorrowOpeningFee > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
    }

    /// @notice Setter of the fee recipient for the market.
    /// @param _feeRecipient The new fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        uint256 protocolFeePercentage = IAltoLiquidationEngine(liquidationEngine).protocolFeePercentage();
        if (_feeRecipient == address(0) && (borrowOpeningFee() > 0 || protocolFeePercentage > 0 || interestFee > 0)) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    /// @notice Setter of the interest fee
    /// @param _newInterestFee The new interest fee
    /// @param _skipAccrueInterest Whether to skip accruing interest
    function setInterestFee(uint256 _newInterestFee, bool _skipAccrueInterest) external onlyOwner {
        if (_newInterestFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _newInterestFee > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (!paused[PAUSE_TYPE] && !_skipAccrueInterest) {
            _accrueInterest();
        }

        emit SetInterestFee(interestFee, _newInterestFee);
        interestFee = _newInterestFee;
    }

    function setSupplyCap(uint128 _newSupplyCapAssets) external onlyOwner {
        emit SetSupplyCap(supplyCapAssets, _newSupplyCapAssets);
        supplyCapAssets = _newSupplyCapAssets;
    }
}
