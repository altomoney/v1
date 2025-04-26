// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Utils} from "./libraries/Utils.sol";

import {IUsdo} from "tapioca-bar/usdo/IUsdo.sol";

import {IIrm} from "./interfaces/IIrm.sol";
import {Balance, Position, LiquidationConfiguration, LiquidationResult} from "./interfaces/IMarket.sol";

import {AltoBorrowMarket} from "./AltoBorrowMarket.sol";

contract AltoMintMarket is AltoBorrowMarket {
    using Utils for uint256;

    error Alto_MintMarket_NotImplemented();

    uint128 public claimableAccruedDebt;
    address public interestReceiver;

    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _debtCeiling,
        address _interestReceiver,
        LiquidationConfiguration memory _liquidationConfiguration
    ) AltoBorrowMarket(_borrowToken, _collateralToken, _irm, _owner, _oracle, _maxLtv, _liquidationConfiguration) {
        totalSupply.assets = _debtCeiling.toUint128();
        interestReceiver = _interestReceiver;
    }

    function setInterestReceiver(address _interestReceiver) external onlyOwner {
        interestReceiver = _interestReceiver;
    }

    function setDebtCeiling(uint256 _debtCeiling) external onlyOwner {
        if (totalBorrowed.assets > _debtCeiling) {
            revert AltoBorrowMarketInsufficientMarketLiquidity();
        }

        totalSupply.assets = _debtCeiling.toUint128();
    }

    function addSupply(uint256 assets, uint256 shares) external override returns (uint256, uint256) {
        revert Alto_MintMarket_NotImplemented();
    }

    function removeSupply(uint256 assets, uint256 shares) external override returns (uint256, uint256) {
        revert Alto_MintMarket_NotImplemented();
    }

    function _accrueInterest() internal override {
        (uint256 borrowRate, uint256 interest) = IIrm(irm).updateInterestRate(totalSupply.assets, totalBorrowed.assets);

        totalBorrowed.assets += interest.toUint128();
        claimableAccruedDebt += interest.toUint128();

        emit AccrueInterest(borrowRate, interest, totalBorrowed.assets, totalSupply.assets);
    }

    function _sendBorrowToken(address from, address to, uint256 amount) internal override {
        if (from == address(this)) {
            IUsdo(borrowToken).mint(to, amount);
        } else {
            IUsdo(borrowToken).burn(from, amount);
        }
    }

    function claimInterest() external {
        uint256 interest = claimableAccruedDebt;
        IUsdo(borrowToken).mint(interestReceiver, interest);
        claimableAccruedDebt = 0;
    }
}
