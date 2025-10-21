// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "./AltoBaseMarket.sol";
import {LiquidationConfiguration} from "./interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

/// @title Alto Borrow Market
/// @author Pearl Labs
/// @custom:contact security@tapioca.xyz
/// @notice An Isolated Borrow Market
contract AltoBorrowMarket is AltoBaseMarket {
    /// @notice Thrown when the input is invalid
    error AltoBorrowMarketInvalidInput();

    /// @notice Emitted when the borrow opening fee is set
    /// @param oldBorrowOpeningFee The old borrow opening fee
    /// @param newBorrowOpeningFee The new borrow opening fee
    event SetBorrowOpeningFee(uint256 oldBorrowOpeningFee, uint256 newBorrowOpeningFee);

    uint256 private _borrowOpeningFee;

    /// upgrade gap
    uint256[49] private __gap_borrow;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFeeWad,
        address _feeRecipient,
        LiquidationConfiguration memory _liquidationConfiguration
    ) public initializer {
        __AltoBaseMarket_init(
            _borrowToken, _collateralToken, _irm, _owner, _oracle, _maxLtv, _feeRecipient, _liquidationConfiguration
        );

        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }
        if (_feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        _borrowOpeningFee = _borrowOpeningFeeWad;
        emit SetBorrowOpeningFee(0, _borrowOpeningFeeWad);
    }

    /// @notice Getter of the borrow opening fee
    /// @return The borrow opening fee
    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    /// @notice Setter of the borrow opening fee
    /// @param _borrowOpeningFeeWad The new borrow opening fee
    function setBorrowOpeningFee(uint256 _borrowOpeningFeeWad) external onlyOwner {
        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBorrowMarketInvalidInput();
        }

        if (feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBorrowMarketInvalidInput();
        }

        emit SetBorrowOpeningFee(_borrowOpeningFee, _borrowOpeningFeeWad);
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }
}
