// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Uint128Converter} from "./libraries/Uint128Converter.sol";

import {IIrm} from "./interfaces/IIrm.sol";
import {Balance, Position, LiquidationConfiguration} from "./interfaces/IMarket.sol";
import {IMintableERC20} from "./interfaces/IMintableERC20.sol";

import {AltoBorrowMarket} from "./AltoBorrowMarket.sol";

/// @title Alto Mint Market
/// @author Alto Foundation
/// @custom:contact security@alto.xyz
/// @notice An Isolated Mint Market
contract AltoMintMarket is AltoBorrowMarket {
    using Uint128Converter for uint256;

    error AltoMintMarketNotImplemented();

    uint128 public claimableFeesAssets;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _debtCeiling,
        address _feeRecipient,
        uint256 _borrowOpeningFee,
        LiquidationConfiguration memory _liquidationConfiguration
    )
        AltoBorrowMarket(
            _borrowToken,
            _collateralToken,
            _irm,
            _owner,
            _oracle,
            _maxLtv,
            _borrowOpeningFee,
            _feeRecipient,
            _liquidationConfiguration
        )
    {
        totalSupply.assets = _debtCeiling.toUint128();
    }

    function setDebtCeiling(uint256 _debtCeiling) external onlyOwner {
        if (totalBorrowed.assets > _debtCeiling) {
            revert AltoBorrowMarketInsufficientMarketLiquidity();
        }

        totalSupply.assets = _debtCeiling.toUint128();
    }

    /// @dev Disabled on mint market
    function addSupply(uint256, uint256, address) external override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
    }

    /// @dev Disabled on mint market
    function removeSupply(uint256, uint256, address, address) external override returns (uint256, uint256) {
        revert AltoMintMarketNotImplemented();
    }

    function _accrueInterest() internal override {
        if (irm == address(0)) {
            return;
        }

        (uint256 borrowRate, uint256 interest) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

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

        position[borrower].borrowShares = 0;
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IMintableERC20(borrowToken).mint(to, amount);
        } else {
            IMintableERC20(borrowToken).burn(from, amount);
        }
    }

    function claimInterest() external {
        uint256 interest = claimableFeesAssets;
        IMintableERC20(borrowToken).mint(feeRecipient, interest);
        claimableFeesAssets = 0;
    }
}
