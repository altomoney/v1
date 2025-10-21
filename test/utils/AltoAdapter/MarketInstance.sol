// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBaseMarket} from "@alto/lending/AltoBaseMarket.sol";
import {LiquidationConfiguration} from "@alto/lending/interfaces/IMarket.sol";
import {MATH_PRECISION} from "@alto/utils/FixedPointMath.sol";

contract MarketInstance is AltoBaseMarket {
    uint256 private _borrowOpeningFee;

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
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    function borrowOpeningFee() public view override returns (uint256) {
        return _borrowOpeningFee;
    }

    function setBorrowOpeningFee(uint256 _borrowOpeningFeeWad) external onlyOwner {
        if (_borrowOpeningFeeWad > MATH_PRECISION) {
            revert AltoBaseMarketInvalidInput();
        }
        if (feeRecipient == address(0) && _borrowOpeningFeeWad > 0) {
            revert AltoBaseMarketInvalidInput();
        }
        _borrowOpeningFee = _borrowOpeningFeeWad;
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
