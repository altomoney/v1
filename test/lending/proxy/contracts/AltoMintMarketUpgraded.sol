// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Uint128Converter} from "@alto/lending/libraries/Uint128Converter.sol";
import {AltoBaseMarketUpgraded} from "./AltoBaseMarketUpgraded.sol";
import {Balance, MintMarketInitParams, MarketType} from "@alto/lending/interfaces/IMarket.sol";
import {IIrm} from "@alto/lending/interfaces/IIrm.sol";
import {IAltoLiquidationEngine} from "@alto/lending/interfaces/IAltoLiquidationEngine.sol";
import {IMintableERC20} from "@alto/lending/interfaces/IMintableERC20.sol";
import {PAUSE_TYPE} from "@alto/utils/Constants.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @custom:oz-upgrades-from AltoMintMarket
contract AltoMintMarketUpgraded is AltoBaseMarketUpgraded {
    using Uint128Converter for uint256;

    error AltoMintMarketNotImplemented();
    error AltoMintMarketInvalidInput();

    event SetDebtCeiling(uint256 oldDebtCeiling, uint256 newDebtCeiling);
    event InterestClaimed(uint256 amount);
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);
    event BadDebtAccrued(uint256 badDebtAmount);

    uint128 public claimableFeesAssets;

    uint256 private _borrowOpeningFee;

    uint128 public badDebtAssets;

    uint256[47] private __gap_mint;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(MintMarketInitParams memory _initParams) public initializer {
        __AltoBaseMarket_init(_initParams.baseMarketInitParams, MarketType.MINT);

        if (_initParams.initialBorrowOpeningFee > MATH_PRECISION) {
            revert AltoMintMarketInvalidInput();
        }
        if (_initParams.baseMarketInitParams.feeRecipient == address(0) && _initParams.initialBorrowOpeningFee > 0) {
            revert AltoMintMarketInvalidInput();
        }
        if (_initParams.baseMarketInitParams.feeRecipient == address(0) && irm != address(0)) {
            revert AltoMintMarketInvalidInput();
        }

        _borrowOpeningFee = _initParams.initialBorrowOpeningFee;
        emit SetBorrowOpeningFee(0, _initParams.initialBorrowOpeningFee);

        totalSupply.assets = _initParams.debtCeiling.toUint128();
        emit SetDebtCeiling(0, _initParams.debtCeiling);
    }

    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function setBorrowOpeningFee(uint256 _newBorrowOpeningFee) external onlyOwner {
        if (_newBorrowOpeningFee > MATH_PRECISION) {
            revert AltoMintMarketInvalidInput();
        }
        if (feeRecipient == address(0) && _newBorrowOpeningFee > 0) {
            revert AltoMintMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _newBorrowOpeningFee);
        _borrowOpeningFee = _newBorrowOpeningFee;
    }

    function setDebtCeiling(uint256 _debtCeiling) external onlyOwner {
        if (!paused[PAUSE_TYPE]) {
            _accrueInterest();
        }

        if (totalBorrowed.assets + badDebtAssets > _debtCeiling) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        emit SetDebtCeiling(totalSupply.assets, _debtCeiling);
        totalSupply.assets = _debtCeiling.toUint128();
    }

    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        uint256 protocolFeePercentage = IAltoLiquidationEngine(liquidationEngine).protocolFeePercentage();
        if (_feeRecipient == address(0) && (borrowOpeningFee() > 0 || protocolFeePercentage > 0 || irm != address(0))) {
            revert AltoMintMarketInvalidInput();
        }

        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function initializeV2(uint256 _addedProperty1, uint256 _addedProperty2, address _addedProperty3)
        public
        virtual
        reinitializer(2)
    {
        addedProperty1 = _addedProperty1;
        addedProperty2 = _addedProperty2;
        addedProperty3 = _addedProperty3;
    }

    function setAddedProperty1(uint256 value) external {
        addedProperty1 = value;
    }

    function setAddedProperty2(uint256 value) external {
        addedProperty2 = value;
    }

    function setAddedProperty3(address value) external {
        addedProperty3 = value;
    }

    function claimInterest(uint256 interest) public whenNotPaused returns (uint256) {
        if (feeRecipient == address(0) || interest > claimableFeesAssets) {
            revert AltoBaseMarketInvalidInput();
        }

        return _claimInterest(interest);
    }

    function _borrow(uint256 assets, uint256 shares, address onBehalf, address receiver, bytes calldata swapParams)
        internal
        override
        returns (uint256, uint256, uint256)
    {
        uint256 openingFeeAssets;

        (assets, shares, openingFeeAssets) = super._borrow(assets, shares, onBehalf, receiver, swapParams);

        if (totalBorrowed.assets + badDebtAssets > totalSupply.assets) {
            revert AltoBaseMarketInsufficientMarketLiquidity();
        }

        return (assets, shares, openingFeeAssets);
    }

    function _addSupply(uint256, uint256, address) internal pure override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
    }

    function _removeSupply(uint256, uint256, address, address) internal pure override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
    }

    function _accrueInterest() internal override {
        if (irm == address(0)) {
            return;
        }

        (uint256 interest, uint256 borrowRate) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        if (interest == 0) {
            return;
        }

        totalBorrowed.assets += interest.toUint128();
        claimableFeesAssets += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    function _applyBorrowOpeningFee(uint256 openingFeeAssets) internal override returns (uint256) {
        claimableFeesAssets += openingFeeAssets.toUint128();

        return 0;
    }

    function _applyLiquidationBadDebt(Balance memory badDebt, address borrower) internal override {
        totalBorrowed.shares -= badDebt.shares;
        totalBorrowed.assets -= badDebt.assets;

        badDebtAssets += badDebt.assets;
        emit BadDebtAccrued(badDebt.assets);

        position[borrower].borrowShares = 0;
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    function _claimInterest(uint256 interest) internal returns (uint256) {
        if (interest == 0) {
            interest = claimableFeesAssets;
        }

        IMintableERC20(borrowToken).mint(feeRecipient, interest);
        claimableFeesAssets -= interest.toUint128();

        emit InterestClaimed(interest);

        return interest;
    }

    function _repay(uint256 assets, uint256 shares, address onBehalf) internal override returns (uint256, uint256) {
        _accrueInterest();

        if (claimableFeesAssets > 0) {
            _claimInterest(0);
        }

        return super._repay(assets, shares, onBehalf);
    }

    function _liquidate(address borrower, bytes calldata callbackData, bytes memory liquidationData)
        internal
        override
        returns (uint256, uint256, uint256)
    {
        _accrueInterest();

        if (claimableFeesAssets > 0) {
            _claimInterest(0);
        }

        return super._liquidate(borrower, callbackData, liquidationData);
    }
}
