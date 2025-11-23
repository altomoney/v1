// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "./AltoBaseMarket.sol";
import {BorrowMarketInitParams, LiquidationConfiguration, MarketType} from "./interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title Alto Borrow Market
/// @author Pearl Labs
/// @custom:contact security@altofoundation.org
/// @notice An Isolated Borrow Market
contract AltoBorrowMarket is AltoBaseMarket {
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

    /// @notice The borrow opening fee in MATH_PRECISION
    uint256 private _borrowOpeningFee;

    /// @notice The maximum amount of assets that can be supplied to the market
    uint128 public supplyCapAssets;

    /// upgrade gap
    uint256[48] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(BorrowMarketInitParams memory _initParams) public initializer {
        __AltoBaseMarket_init(_initParams.baseMarketInitParams, MarketType.BORROW);

        if (_initParams.initialBorrowOpeningFee > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_initParams.baseMarketInitParams.feeRecipient == address(0) && _initParams.initialBorrowOpeningFee > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

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

    function setSupplyCap(uint128 _newSupplyCapAssets) external onlyOwner {
        emit SetSupplyCap(supplyCapAssets, _newSupplyCapAssets);
        supplyCapAssets = _newSupplyCapAssets;
    }
}
