// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AltoBorrowMarket} from "@alto-monorepo/lending/AltoBorrowMarket.sol";
import {LiquidationConfiguration} from "@alto-monorepo/lending/interfaces/IMarket.sol";

contract MarketInstance is AltoBorrowMarket {
    constructor(
        address _borrowToken,
        address _collateralToken,
        address _irm,
        address _owner,
        address _oracle,
        uint256 _maxLtv,
        uint256 _borrowOpeningFee,
        address _feeRecipient,
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
    {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function authorizationTypeHash() public view returns (bytes32) {
        return _AUTHORIZATION_TYPEHASH;
    }
}
