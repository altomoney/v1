// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/// @dev Minimal market mock exposing collateralToken for swapper BTT tests.
contract MarketMock {
    address public collateralToken;

    constructor(address _collateralToken) {
        collateralToken = _collateralToken;
    }
}
